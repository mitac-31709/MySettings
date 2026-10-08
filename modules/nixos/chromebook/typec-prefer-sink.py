"""Chromebook USB-C power-role policy via Cros EC.

Goals
-----
- Power bank (on battery): become sink and charge the laptop.
- Phone / other peripherals: source (charge the accessory).
- While AC is powering the laptop: other ports source so phones charge.

sysfs PR_SWAP often returns EIO. Mid-connect FORCE_SINK can drop the link
into a useless 5V/500mA ghost — use soft-reset (TOGGLE_OFF → FORCE_*) instead.
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

USB_PD_CTRL_ROLE_TOGGLE_OFF = 2
USB_PD_CTRL_ROLE_FORCE_SINK = 3
USB_PD_CTRL_ROLE_FORCE_SOURCE = 4
USB_PD_CTRL_MUX_NO_CHANGE = 0
USB_PD_CTRL_SWAP_NONE = 0

OVERRIDE_OFF = -1
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
    keys = ("online", "status", "voltage_now", "current_max", "usb_type")
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


def system_on_ac() -> bool:
    if read_text(Path("/sys/class/power_supply/AC/online")) == "1":
        return True
    return any(charger_useful(p) for p in list_typec_ports())


def is_ac_input_port(port: int) -> bool:
    """Port currently supplying useful input power (dedicated charger / PD)."""
    role = power_role(port)
    return charger_useful(port) and not is_sourcing(role)


def partner_source_caps(port: int) -> list[Path]:
    base = Path(f"/sys/class/typec/port{port}-partner/pd0/source-capabilities")
    if not base.is_dir():
        return []
    return list(base.glob("*:fixed_supply")) + list(
        base.glob("*:programmable_supply")
    )


def partner_type(port: int) -> str:
    return read_text(Path(f"/sys/class/typec/port{port}-partner/type"))


def is_likely_power_bank(port: int) -> bool:
    """Power banks advertise source PDOs / product type psd even while sinking."""
    partner = Path(f"/sys/class/typec/port{port}-partner")
    if not partner.exists():
        return False
    ptype = partner_type(port)
    if ptype == "psd":
        return True
    # Wall bricks are source-only from our POV while we sink with useful charge.
    if is_ac_input_port(port):
        return False
    return bool(partner_source_caps(port))


def is_likely_wall_charger(port: int) -> bool:
    """Dedicated PSU / brick, including 5V ghost while we wrongly stay source.

    Idle FORCE_SOURCE + wall brick → partner present, online=0, still [source].
    Phones are usually type=ufp; bricks often not_ufp with
    supports_usb_power_delivery=no until we become sink.
    """
    partner = Path(f"/sys/class/typec/port{port}-partner")
    if not partner.exists() or is_ac_input_port(port):
        return False
    ptype = partner_type(port)
    supports_pd = read_text(partner / "supports_usb_power_delivery")
    if ptype == "not_ufp" and supports_pd != "yes":
        return True
    snap = charger_snapshot(port)
    try:
        voltage = int(snap.get("voltage_now") or "0")
        current_max = int(snap.get("current_max") or "0")
        online = int(snap.get("online") or "0")
    except ValueError:
        return False
    return (
        online == 0
        and is_sourcing(power_role(port))
        and ptype != "ufp"
        and voltage >= 4_500_000
        and current_max >= MIN_USEFUL_CURRENT_UA
    )


def soft_reset(fd: int, port: int, role: int, settle: float) -> None:
    name = "FORCE_SINK" if role == USB_PD_CTRL_ROLE_FORCE_SINK else "FORCE_SOURCE"
    print(f"port{port}: soft-reset TOGGLE_OFF → {name}")
    try:
        charge_override_off(fd)
    except EcError as e:
        print(f"port{port}: override off: {e}", file=sys.stderr)
    pd_control(fd, port, USB_PD_CTRL_ROLE_TOGGLE_OFF)
    time.sleep(max(settle, 0.8))
    pd_control(fd, port, role)


def set_idle_role(fd: int, port: int, role: int) -> None:
    name = "FORCE_SINK" if role == USB_PD_CTRL_ROLE_FORCE_SINK else "FORCE_SOURCE"
    print(f"port{port}: idle {name}")
    pd_control(fd, port, role)


def wait_sink_charge(fd: int, port: int, settle: float, retries: int) -> bool:
    for i in range(retries):
        time.sleep(settle)
        role = power_role(port)
        partner = has_partner(port)
        snap = charger_snapshot(port)
        print(
            f"port{port}: sink-wait {i + 1}/{retries} role={role or '?'} "
            f"partner={partner} charger={snap}"
        )
        if partner and not is_sourcing(role or "") and charger_useful(port):
            try:
                charge_override(fd, port)
                print(f"port{port}: chargeoverride {port}")
            except EcError as e:
                print(f"port{port}: chargeoverride: {e}", file=sys.stderr)
            time.sleep(0.5)
            if charger_useful(port):
                return True
        if partner and is_sourcing(role or ""):
            soft_reset(fd, port, USB_PD_CTRL_ROLE_FORCE_SINK, settle)
    return charger_useful(port)


def wait_source(port: int, settle: float, retries: int) -> bool:
    for i in range(retries):
        time.sleep(settle)
        role = power_role(port)
        partner = has_partner(port)
        print(
            f"port{port}: source-wait {i + 1}/{retries} role={role or '?'} "
            f"partner={partner}"
        )
        if partner and is_sourcing(role or ""):
            return True
        if not partner:
            # Idle after reset — FORCE_SOURCE already set for next attach.
            return True
    return is_sourcing(power_role(port))


def ensure_sink(fd: int, port: int, settle: float, retries: int) -> bool:
    role = power_role(port)
    if has_partner(port) and not is_sourcing(role) and charger_useful(port):
        try:
            charge_override(fd, port)
        except EcError as e:
            print(f"port{port}: chargeoverride: {e}", file=sys.stderr)
        print(f"port{port}: already sinking with useful charge")
        return True
    if has_partner(port):
        soft_reset(fd, port, USB_PD_CTRL_ROLE_FORCE_SINK, settle)
        return wait_sink_charge(fd, port, settle, retries)
    set_idle_role(fd, port, USB_PD_CTRL_ROLE_FORCE_SINK)
    return True


def ensure_source(fd: int, port: int, settle: float, retries: int) -> bool:
    role = power_role(port)
    if has_partner(port) and is_sourcing(role):
        print(f"port{port}: already sourcing")
        return True
    if has_partner(port):
        soft_reset(fd, port, USB_PD_CTRL_ROLE_FORCE_SOURCE, settle)
        return wait_source(port, settle, retries)
    set_idle_role(fd, port, USB_PD_CTRL_ROLE_FORCE_SOURCE)
    return True


def desired_role(port: int) -> str:
    """Return 'sink', 'source', or 'leave' for this port."""
    on_ac = system_on_ac()
    partner = has_partner(port)

    if is_ac_input_port(port):
        return "leave"

    if on_ac:
        # AC feeding the laptop → every other port should output.
        return "source"

    if not partner:
        # On battery, idle ports prefer source so phones charge on plug.
        # Wall bricks that attach into this state are fixed by
        # is_likely_wall_charger() → sink on the plug event.
        return "source"

    if is_likely_power_bank(port) or is_likely_wall_charger(port):
        return "sink"

    # Phone / hub / peripheral.
    return "source"


def handle_port(fd: int, port: int, settle: float, retries: int) -> bool:
    role = power_role(port)
    want = desired_role(port)
    bank = is_likely_power_bank(port) if has_partner(port) else False
    wall = is_likely_wall_charger(port) if has_partner(port) else False
    print(
        f"port{port}: role={role or '?'} partner={has_partner(port)} "
        f"bank={bank} wall={wall} on_ac={system_on_ac()} want={want} "
        f"charger={charger_snapshot(port)}"
    )
    if want == "leave":
        print(f"port{port}: AC input — leave sink")
        return True
    if want == "sink":
        return ensure_sink(fd, port, settle, retries)
    return ensure_source(fd, port, settle, retries)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, action="append")
    parser.add_argument("--settle", type=float, default=1.0)
    parser.add_argument("--retries", type=int, default=8)
    parser.add_argument(
        "--boot",
        action="store_true",
        help="Boot/idle policy only (no long waits)",
    )
    # Compat with older unit files.
    parser.add_argument("--force-all-sink", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.force_all_sink:
        args.boot = True

    if not os.access(EC_DEV, os.R_OK | os.W_OK):
        print(f"cannot access {EC_DEV} (need root)", file=sys.stderr)
        return 1

    settle = 0.2 if args.boot else args.settle
    retries = 1 if args.boot else args.retries

    with open(EC_DEV, "r+b", buffering=0) as ec:
        fd = ec.fileno()
        ports = args.port if args.port is not None else list_typec_ports()
        if not ports:
            print("no typec ports")
            return 0

        if not system_on_ac():
            try:
                # Drop stale overrides when running on battery only.
                if not any(charger_useful(p) for p in ports):
                    charge_override_off(fd)
            except EcError as e:
                print(f"override off: {e}", file=sys.stderr)

        # Let partner PD identity / source-caps show up before classification.
        if not args.boot and any(has_partner(p) for p in ports):
            time.sleep(max(settle, 0.8))

        any_ok = False
        for port in ports:
            if handle_port(fd, port, settle, retries):
                any_ok = True
        return 0 if any_ok else 2


if __name__ == "__main__":
    sys.exit(main())
