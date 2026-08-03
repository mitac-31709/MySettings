"""Chromebook-like power-button chords across separate input devices.

The ACPI power button (LNXPWRBN) and the keyboard are different evdev nodes,
so keyd cannot chord them. This watcher:

  power short press     → suspend
  power long press      → poweroff (~2.5s; EC still hard-cuts ~10s)
  power + Back          → force-logout (terminate-user)
  power + Refresh       → reboot

Back/Refresh are read from keyd's virtual keyboard (after top-row remaps).

Chord order does not matter: Back/Refresh may be pressed before or after Power.
On Power release, a short grace window still accepts Back/Refresh before suspend
(covers near-simultaneous taps where Power comes up slightly first).
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
# After starting suspend, ignore further short-presses briefly (resume bounce /
# "suspend already in progress" spam).
SUSPEND_COOLDOWN_SEC = 3.0
# After Power key-up, wait this long for a late Back/Refresh before suspending.
CHORD_GRACE_SEC = 0.4

# keyd remaps top-row to KEY_BACK / KEY_REFRESH; also accept bare F1/F2 in case
# the virtual keyboard still surfaces those codes.
BACK_CODES = frozenset(
    c
    for c in (
        getattr(ecodes, "KEY_BACK", None),
        getattr(ecodes, "KEY_F1", None),
    )
    if c is not None
)
REFRESH_CODES = frozenset(
    c
    for c in (
        getattr(ecodes, "KEY_REFRESH", None),
        getattr(ecodes, "KEY_F2", None),
    )
    if c is not None
)


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

    log(
        f"watching {power.path} ({power.name}) + {keyd.path} ({keyd.name}) "
        f"for user {user}; back={sorted(BACK_CODES)} refresh={sorted(REFRESH_CODES)} "
        f"grace={CHORD_GRACE_SEC}s"
    )

    power_down_at: float | None = None
    combo_used = False
    back_held = False
    refresh_held = False
    suspend_cooldown_until = 0.0
    # When set, a short press is pending suspend until this monotonic time
    # (or until a chord arrives / cooldown blocks it).
    pending_suspend_until: float | None = None
    devices = {power.fd: power, keyd.fd: keyd}

    def trigger_logout() -> None:
        nonlocal combo_used, pending_suspend_until
        combo_used = True
        pending_suspend_until = None
        run(["loginctl", "terminate-user", user])

    def trigger_reboot() -> None:
        nonlocal combo_used, pending_suspend_until
        combo_used = True
        pending_suspend_until = None
        run(["systemctl", "reboot"])

    def maybe_chord_from_held() -> None:
        """If Power just went down while Back/Refresh already held."""
        if combo_used or power_down_at is None:
            return
        if back_held:
            log("chord: power while Back held → logout")
            trigger_logout()
        elif refresh_held:
            log("chord: power while Refresh held → reboot")
            trigger_reboot()

    def arm_pending_suspend() -> None:
        nonlocal pending_suspend_until
        if time.monotonic() < suspend_cooldown_until:
            pending_suspend_until = None
            return
        pending_suspend_until = time.monotonic() + CHORD_GRACE_SEC

    while True:
        try:
            r, _, _ = select.select(list(devices), [], [], 0.05)
        except (OSError, ValueError):
            log("select failed; reopening devices")
            return 1

        now = time.monotonic()

        # Flush deferred short-press suspend after the chord grace window.
        if (
            pending_suspend_until is not None
            and now >= pending_suspend_until
            and not combo_used
        ):
            pending_suspend_until = None
            if now >= suspend_cooldown_until:
                run(["systemctl", "suspend"])
                suspend_cooldown_until = now + SUSPEND_COOLDOWN_SEC

        # Long-press poweroff while still held.
        if power_down_at is not None and not combo_used:
            held = now - power_down_at
            if held >= LONG_PRESS_SEC:
                combo_used = True
                pending_suspend_until = None
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
                            pending_suspend_until = None
                            maybe_chord_from_held()
                        elif key.keystate == 0:
                            if power_down_at is not None and not combo_used:
                                arm_pending_suspend()
                            power_down_at = None
                            # Keep combo_used if a chord already fired; otherwise
                            # clear so the grace window can still accept Back.
                            if combo_used:
                                pending_suspend_until = None
                            else:
                                combo_used = False
                        continue

                    if dev is keyd:
                        power_or_grace = (
                            power_down_at is not None or pending_suspend_until is not None
                        )
                        if key.keystate == 1 and power_or_grace and not combo_used:
                            if code not in BACK_CODES and code not in REFRESH_CODES:
                                log(
                                    f"key while power/grace: code={code} "
                                    f"name={getattr(key, 'keycode', '?')}"
                                )

                        if code in BACK_CODES:
                            if key.keystate == 1:
                                back_held = True
                                if power_or_grace and not combo_used:
                                    log("chord: Back while power/grace → logout")
                                    trigger_logout()
                            else:
                                back_held = False
                        elif code in REFRESH_CODES:
                            if key.keystate == 1:
                                refresh_held = True
                                if power_or_grace and not combo_used:
                                    log("chord: Refresh while power/grace → reboot")
                                    trigger_reboot()
                            else:
                                refresh_held = False
            except OSError as err:
                log(f"read error on {dev.name}: {err}")
                return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
