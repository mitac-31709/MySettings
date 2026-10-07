"""Force Cros EC USB-C ports to sink so power banks charge the Chromebook.

sysfs power_role swaps (PR_SWAP) often return EIO: the EC accepts the command
but the partner keeps us as source (Try.SRC win). USB_PD_CTRL_ROLE_FORCE_SINK
renegotiates CC as sink; charge-port override then selects that port for input.
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

# linux/platform_data/cros_ec_chardev.h — sizeof(struct cros_ec_command) without flex array
CROS_EC_DEV_IOCXCMD = 0xC014EC00

EC_CMD_USB_PD_CONTROL = 0x0101
EC_CMD_PD_CHARGE_PORT_OVERRIDE = 0x0114
EC_RES_SUCCESS = 0

USB_PD_CTRL_ROLE_FORCE_SINK = 3
USB_PD_CTRL_MUX_NO_CHANGE = 0
USB_PD_CTRL_SWAP_NONE = 0


class EcError(RuntimeError):
    pass


def ec_command(fd: int, cmd: int, version: int, out: bytes, insize: int) -> bytes:
    # struct cros_ec_command { u32 version, command, outsize, insize, result; u8 data[]; }
    outsize = len(out)
    buf_size = max(outsize, insize)
    data = bytearray(20 + buf_size)
    struct.pack_into("<IIIII", data, 0, version, cmd, outsize, insize, 0)
    data[20:20 + outsize] = out
    fcntl.ioctl(fd, CROS_EC_DEV_IOCXCMD, data, True)
    version, command, outsize, insize_out, result = struct.unpack_from("<IIIII", data, 0)
    if result != EC_RES_SUCCESS:
        raise EcError(f"EC cmd 0x{cmd:x} v{version} result={result}")
    return bytes(data[20:20 + insize])


def pd_control(
    fd: int,
    port: int,
    role: int,
    mux: int = USB_PD_CTRL_MUX_NO_CHANGE,
    swap: int = USB_PD_CTRL_SWAP_NONE,
    version: int = 2,
) -> bytes:
    req = struct.pack("BBBB", port, role, mux, swap)
    # v2 response is larger; request enough space
    return ec_command(fd, EC_CMD_USB_PD_CONTROL, version, req, 48)


def charge_override(fd: int, port: int) -> None:
    # int16_t override_port
    ec_command(fd, EC_CMD_PD_CHARGE_PORT_OVERRIDE, 0, struct.pack("<h", port), 0)


def read_sysfs_power_role(port: int) -> str:
    path = Path(f"/sys/class/typec/port{port}/power_role")
    if not path.exists():
        return ""
    return path.read_text().strip()


def ports_with_partners() -> list[int]:
    ports: list[int] = []
    for partner in Path("/sys/class/typec").glob("port*-partner"):
        name = partner.name  # port1-partner
        if not name.endswith("-partner"):
            continue
        try:
            ports.append(int(name[len("port"):-len("-partner")]))
        except ValueError:
            continue
    return sorted(ports)


def is_sourcing(role: str) -> bool:
    # Kernel: TYPEC_SOURCE → "[source] sink"
    return role.startswith("[source]")


def prefer_sink_port(
    fd: int, port: int, settle: float, retries: int, *, always_force: bool
) -> bool:
    role = read_sysfs_power_role(port)
    print(f"port{port}: power_role={role or '?'}")
    has_partner = Path(f"/sys/class/typec/port{port}-partner").exists()

    if role and not is_sourcing(role) and has_partner and not always_force:
        print(f"port{port}: already sink — charge override only")
        try:
            charge_override(fd, port)
            print(f"port{port}: chargeoverride {port}")
        except EcError as e:
            print(f"port{port}: chargeoverride skipped: {e}", file=sys.stderr)
        return True

    print(f"port{port}: FORCE_SINK" + (" + chargeoverride" if has_partner else ""))
    try:
        pd_control(fd, port, role=USB_PD_CTRL_ROLE_FORCE_SINK)
    except EcError as e:
        print(f"port{port}: FORCE_SINK failed: {e}", file=sys.stderr)
        return False

    if has_partner:
        try:
            charge_override(fd, port)
            print(f"port{port}: chargeoverride {port}")
        except EcError as e:
            print(f"port{port}: chargeoverride failed: {e}", file=sys.stderr)

    if not has_partner:
        # Idle policy only — no contract to verify.
        return True

    ok = False
    for i in range(retries):
        time.sleep(settle)
        role = read_sysfs_power_role(port)
        print(f"port{port}: attempt {i + 1}/{retries} power_role={role}")
        if role and not is_sourcing(role):
            ok = True
            break
        try:
            pd_control(fd, port, role=USB_PD_CTRL_ROLE_FORCE_SINK)
        except EcError as e:
            print(f"port{port}: FORCE_SINK retry failed: {e}", file=sys.stderr)

    # Keep FORCE_SINK (do not return to auto/Try.SRC).
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--port",
        type=int,
        action="append",
        help="Type-C port number (default: ports with a partner)",
    )
    parser.add_argument("--settle", type=float, default=1.0)
    parser.add_argument("--retries", type=int, default=5)
    parser.add_argument(
        "--force-all-sink",
        action="store_true",
        help="FORCE_SINK on every Type-C port even without a partner (idle preference)",
    )
    args = parser.parse_args()

    if not os.access(EC_DEV, os.R_OK | os.W_OK):
        print(f"cannot access {EC_DEV} (need root)", file=sys.stderr)
        return 1

    ports = args.port
    if ports is None:
        ports = ports_with_partners()
        if args.force_all_sink:
            for p in Path("/sys/class/typec").glob("port[0-9]*"):
                if p.name.count("-"):
                    continue
                try:
                    n = int(p.name[len("port"):])
                except ValueError:
                    continue
                if n not in ports:
                    ports.append(n)
            ports = sorted(ports)

    if not ports:
        print("no typec partners; nothing to do")
        return 0

    with open(EC_DEV, "r+b", buffering=0) as ec:
        fd = ec.fileno()
        any_ok = False
        for port in ports:
            if prefer_sink_port(
                fd,
                port,
                args.settle,
                args.retries,
                always_force=args.force_all_sink,
            ):
                any_ok = True
        return 0 if any_ok else 2


if __name__ == "__main__":
    sys.exit(main())
