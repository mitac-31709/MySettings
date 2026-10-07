"""Prefer Cros EC USB-C sink so power banks charge the Chromebook.

Background
----------
delbin Try.SRC often wins against power banks, so the laptop sources into the
bank. sysfs PR_SWAP returns EIO. FORCE_SINK *while connected* can drop the
partner and leave a useless 5V/500mA ghost (0 mAh/min).

Strategy
--------
1. Idle / boot: FORCE_SINK on every port so the *next* attach negotiates as sink.
2. If we are sourcing into a partner: soft-reset the port (TOGGLE_OFF → FORCE_SINK)
   so the bank re-attaches as a source with a real PD contract.
3. Once sink + partner: charge-port override; verify charger current_max > 500mA.
"""

from __future__ import annotations

import argparse
import fcntl
import os
import struct
import sys
import time
from pathlib import Path

EC_DEV = "/dev/cros_ec"
CROS_EC_DEV_IOCXCMD = 0xC014EC00

EC_CMD_USB_PD_CONTROL = 0x0101
EC_CMD_PD_CHARGE_PORT_OVERRIDE = 0x0114
EC_RES_SUCCESS = 0

USB_PD_CTRL_ROLE_TOGGLE_ON = 1
USB_PD_CTRL_ROLE_TOGGLE_OFF = 2
USB_PD_CTRL_ROLE_FORCE_SINK = 3
USB_PD_CTRL_MUX_NO_CHANGE = 0
USB_PD_CTRL_SWAP_NONE = 0

OVERRIDE_OFF = -1

# SDP / ghost floor after a bad FORCE_SINK while connected.
MIN_USEFUL_CURRENT_UA = 600_000


class EcError(RuntimeError):
    pass


def ec_command(fd: int, cmd: int, version: int, out: bytes, insize: int) -> bytes:
    outsize = len(out)
    buf_size = max(outsize, insize)
    data = bytearray(20 + buf_size)
    struct.pack_into("<IIIII", data, 0, version, cmd, outsize, insize, 0)
    data[20:20 + outsize] = out
    fcntl.ioctl(fd, CROS_EC_DEV_IOCXCMD, data, True)
    _v, _c, _o, _i, result = struct.unpack_from("<IIIII", data, 0)
    if result != EC_RES_SUCCESS:
        raise EcError(f"EC cmd 0x{cmd:x} v{version} result={result}")
    return bytes(data[20:20 + insize])


def pd_control(fd: int, port: int, role: int) -> None:
    req = struct.pack(
        "BBBB", port, role, USB_PD_CTRL_MUX_NO_CHANGE, USB_PD_CTRL_SWAP_NONE
    )
    ec_command(fd, EC_CMD_USB_PD_CONTROL, 2, req, 48)


def charge_override(fd: int, port: int) -> None:
    ec_command(fd, EC_CMD_PD_CHARGE_PORT_OVERRIDE, 0, struct.pack("<h", port), 0)


def charge_override_off(fd: int) -> None:
    ec_command(
        fd, EC_CMD_PD_CHARGE_PORT_OVERRIDE, 0, struct.pack("<h", OVERRIDE_OFF), 0
    )


def read_text(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def power_role(port: int) -> str:
    return read_text(Path(f"/sys/class/typec/port{port}/power_role"))


def has_partner(port: int) -> bool:
    return Path(f"/sys/class/typec/port{port}-partner").exists()


def is_sourcing(role: str) -> bool:
    return role.startswith("[source]")


def charger_snapshot(port: int) -> dict[str, str]:
    base = Path(f"/sys/class/power_supply/CROS_USBPD_CHARGER{port}")
    keys = (
        "online",
        "status",
        "voltage_now",
        "current_max",
        "usb_type",
    )
    return {k: read_text(base / k) for k in keys if (base / k).exists()}


def charger_useful(port: int) -> bool:
    snap = charger_snapshot(port)
    try:
        online = int(snap.get("online") or "0")
        current_max = int(snap.get("current_max") or "0")
    except ValueError:
        return False
    return online == 1 and current_max >= MIN_USEFUL_CURRENT_UA


def list_typec_ports() -> list[int]:
    ports: list[int] = []
    for p in Path("/sys/class/typec").glob("port[0-9]*"):
        if "-" in p.name:
            continue
        try:
            ports.append(int(p.name[len("port"):]))
        except ValueError:
            continue
    return sorted(ports)


def ports_with_partners() -> list[int]:
    return [p for p in list_typec_ports() if has_partner(p)]


def force_sink_idle(fd: int, port: int) -> None:
    """Set sink preference for the next cable attach."""
    print(f"port{port}: idle FORCE_SINK")
    pd_control(fd, port, USB_PD_CTRL_ROLE_FORCE_SINK)


def soft_reset_to_sink(fd: int, port: int, settle: float) -> None:
    """Drop the link and come back as forced sink so the bank must source."""
    print(f"port{port}: soft-reset TOGGLE_OFF → FORCE_SINK")
    try:
        charge_override_off(fd)
    except EcError as e:
        print(f"port{port}: override off: {e}", file=sys.stderr)
    pd_control(fd, port, USB_PD_CTRL_ROLE_TOGGLE_OFF)
    time.sleep(max(settle, 0.8))
    pd_control(fd, port, USB_PD_CTRL_ROLE_FORCE_SINK)


def wait_for_useful_charge(fd: int, port: int, settle: float, retries: int) -> bool:
    for i in range(retries):
        time.sleep(settle)
        role = power_role(port)
        partner = has_partner(port)
        snap = charger_snapshot(port)
        print(
            f"port{port}: wait {i + 1}/{retries} role={role or '?'} "
            f"partner={partner} charger={snap}"
        )
        if partner and not is_sourcing(role or "") and charger_useful(port):
            try:
                charge_override(fd, port)
                print(f"port{port}: chargeoverride {port}")
            except EcError as e:
                print(f"port{port}: chargeoverride: {e}", file=sys.stderr)
            # Re-check after override.
            time.sleep(0.5)
            snap = charger_snapshot(port)
            bat = read_text(Path("/sys/class/power_supply/BAT0/status"))
            print(f"port{port}: after override charger={snap} BAT0={bat}")
            if charger_useful(port):
                return True
        if partner and is_sourcing(role or ""):
            # Still sourcing — another soft reset.
            soft_reset_to_sink(fd, port, settle)
    return charger_useful(port)


def handle_port(fd: int, port: int, settle: float, retries: int) -> bool:
    role = power_role(port)
    partner = has_partner(port)
    snap = charger_snapshot(port)
    print(f"port{port}: role={role or '?'} partner={partner} charger={snap}")

    if not partner:
        # Clear ghost 5V/500mA override leftovers, keep sink preference.
        if snap.get("online") == "1" and not charger_useful(port):
            print(f"port{port}: clearing ghost charger / override")
            try:
                charge_override_off(fd)
            except EcError as e:
                print(f"port{port}: override off: {e}", file=sys.stderr)
        force_sink_idle(fd, port)
        print(
            f"port{port}: ready — unplug/replug the power bank if it was connected"
        )
        return True

    if is_sourcing(role):
        soft_reset_to_sink(fd, port, settle)
        return wait_for_useful_charge(fd, port, settle, retries)

    # Already sink with partner — ensure we actually draw power.
    if charger_useful(port):
        try:
            charge_override(fd, port)
            print(f"port{port}: already useful, chargeoverride {port}")
        except EcError as e:
            print(f"port{port}: chargeoverride: {e}", file=sys.stderr)
        return True

    print(f"port{port}: sink but not useful charge — soft-reset")
    soft_reset_to_sink(fd, port, settle)
    return wait_for_useful_charge(fd, port, settle, retries)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, action="append")
    parser.add_argument("--settle", type=float, default=1.0)
    parser.add_argument("--retries", type=int, default=8)
    parser.add_argument(
        "--force-all-sink",
        action="store_true",
        help="Only set idle FORCE_SINK on all ports (boot path)",
    )
    args = parser.parse_args()

    if not os.access(EC_DEV, os.R_OK | os.W_OK):
        print(f"cannot access {EC_DEV} (need root)", file=sys.stderr)
        return 1

    with open(EC_DEV, "r+b", buffering=0) as ec:
        fd = ec.fileno()

        if args.force_all_sink:
            try:
                charge_override_off(fd)
            except EcError as e:
                print(f"override off: {e}", file=sys.stderr)
            for port in list_typec_ports():
                force_sink_idle(fd, port)
            return 0

        ports = args.port if args.port is not None else list_typec_ports()
        # Prefer ports that have partners, but always touch all so idle
        # FORCE_SINK stays set on the free port too.
        if not ports:
            print("no typec ports")
            return 0

        any_ok = False
        for port in ports:
            if handle_port(fd, port, args.settle, args.retries):
                any_ok = True

        if not ports_with_partners():
            print(
                "hint: no partner right now — plug the power bank in after "
                "idle FORCE_SINK, or replug if it dropped"
            )
        return 0 if any_ok else 2


if __name__ == "__main__":
    sys.exit(main())
