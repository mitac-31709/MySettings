"""Chromebook-like power-button chords across separate input devices.

The ACPI power button (LNXPWRBN) and the keyboard are different evdev nodes,
so keyd cannot chord them. This watcher:

  power short press     → suspend
  power long press      → poweroff (~2.5s; EC still hard-cuts ~10s)
  power + Back          → force-logout (terminate-user)
  power + Refresh       → reboot

Back/Refresh are read from keyd's virtual keyboard (after top-row remaps).
"""

from __future__ import annotations

import os
import select
import subprocess
import sys
import time

from evdev import InputDevice, categorize, ecodes, list_devices

POWER_NAME = "Power Button"
KEYD_NAME = "keyd virtual keyboard"
LONG_PRESS_SEC = 2.5
OPEN_RETRY_SEC = 1.0


def log(msg: str) -> None:
    print(f"chromebook-power-chords: {msg}", flush=True)


def find_device(name: str) -> InputDevice | None:
    for path in list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        if dev.name == name:
            return dev
        try:
            dev.close()
        except OSError:
            pass
    return None


def wait_device(name: str) -> InputDevice:
    while True:
        dev = find_device(name)
        if dev is not None:
            return dev
        log(f"waiting for input device {name!r}")
        time.sleep(OPEN_RETRY_SEC)


def run(cmd: list[str]) -> None:
    log("exec: " + " ".join(cmd))
    subprocess.run(cmd, check=False)


def main() -> int:
    user = os.environ.get("POWER_CHORDS_USER", "").strip()
    if not user:
        log("POWER_CHORDS_USER is unset")
        return 1

    power = wait_device(POWER_NAME)
    keyd = wait_device(KEYD_NAME)

    # Own the ACPI power button so logind does not also act on KEY_POWER.
    try:
        power.grab()
    except OSError as err:
        log(f"grab {POWER_NAME} failed: {err}")
        return 1

    log(f"watching {power.path} ({power.name}) + {keyd.path} ({keyd.name}) for user {user}")

    power_down_at: float | None = None
    combo_used = False
    devices = {power.fd: power, keyd.fd: keyd}

    while True:
        try:
            r, _, _ = select.select(list(devices), [], [], 1.0)
        except (OSError, ValueError):
            log("select failed; reopening devices")
            return 1

        # Long-press poweroff while still held.
        if power_down_at is not None and not combo_used:
            held = time.monotonic() - power_down_at
            if held >= LONG_PRESS_SEC:
                combo_used = True
                run(["systemctl", "poweroff"])
                power_down_at = None

        for fd in r:
            dev = devices[fd]
            try:
                for event in dev.read():
                    if event.type != ecodes.EV_KEY:
                        continue
                    key = categorize(event)
                    code = event.code
                    # 1=down 0=up 2=hold
                    if key.keystate == 2:
                        continue

                    if dev is power and code == ecodes.KEY_POWER:
                        if key.keystate == 1:
                            power_down_at = time.monotonic()
                            combo_used = False
                        elif key.keystate == 0:
                            if power_down_at is not None and not combo_used:
                                run(["systemctl", "suspend"])
                            power_down_at = None
                            combo_used = False
                        continue

                    if (
                        dev is keyd
                        and power_down_at is not None
                        and key.keystate == 1
                        and not combo_used
                    ):
                        if code == ecodes.KEY_BACK:
                            combo_used = True
                            run(["loginctl", "terminate-user", user])
                        elif code == ecodes.KEY_REFRESH:
                            combo_used = True
                            run(["systemctl", "reboot"])
            except OSError as err:
                log(f"read error on {dev.name}: {err}")
                return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
