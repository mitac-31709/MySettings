"""Power-button chords across separate input devices (Power Button + keyd).

The ACPI power button (LNXPWRBN / PNP0C0C) and the keyboard are different evdev
nodes, so keyd cannot chord them. This watcher implements:

  power short press       → suspend
  power long press        → poweroff (~2.5s; EC may still hard-cut later)
  power + Back / F1       → force-logout (terminate-user)
  power + Refresh / F2    → reboot

Back/F1 and Refresh/F2 are read from keyd's virtual keyboard (on Chromebook
after top-row remaps; on VAIO directly as F1/F2).

Chord order does not matter: Back/F1 or Refresh/F2 may be pressed before or
after Power. On Power release, a short grace window still accepts Back/F1 or
Refresh/F2 before suspend.
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
# After Power key-up, wait this long for a late Back/F1/Refresh/F2 before suspending.
CHORD_GRACE_SEC = 0.4
# Ignore staggered duplicate Power Button pulses right after a chord fires.
COMBO_DEBOUNCE_SEC = 0.5

# Chromebook keyd remaps top-row to KEY_BACK / KEY_REFRESH; standard PC
# laptops (VAIO) emit KEY_F1 / KEY_F2 on the same keyd virtual keyboard.
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
    print(f"power-chords: {msg}", flush=True)


def close_quietly(devs: list[InputDevice]) -> None:
    for dev in devs:
        try:
            dev.close()
        except OSError:
            pass


def find_power_devices() -> list[InputDevice]:
    """Find all ACPI Power Button evdev nodes (some laptops expose both LNXPWRBN and PNP0C0C)."""
    found: list[InputDevice] = []
    for path in list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        if dev.name == POWER_NAME and ecodes.KEY_POWER in dev.capabilities().get(ecodes.EV_KEY, ()):
            found.append(dev)
        else:
            close_quietly([dev])
    return found


def find_keyd_device() -> InputDevice | None:
    for path in list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        caps = dev.capabilities().get(ecodes.EV_KEY, ())
        if dev.name == KEYD_NAME and ecodes.KEY_F1 in caps:
            return dev
        close_quietly([dev])
    return None


def wait_power_devices() -> list[InputDevice]:
    while True:
        devs = find_power_devices()
        if devs:
            return devs
        log(f"waiting for input device {POWER_NAME!r}")
        time.sleep(OPEN_RETRY_SEC)


def wait_keyd_device() -> InputDevice:
    while True:
        dev = find_keyd_device()
        if dev is not None:
            return dev
        log(f"waiting for input device {KEYD_NAME!r}")
        time.sleep(OPEN_RETRY_SEC)


def run(cmd: list[str]) -> None:
    log("exec: " + " ".join(cmd))
    subprocess.run(cmd, check=False)


def main() -> int:
    user = os.environ.get("POWER_CHORDS_USER", "").strip()
    if not user:
        log("POWER_CHORDS_USER is unset")
        return 1

    power_devs = wait_power_devices()
    keyd = wait_keyd_device()

    # Own all ACPI power button nodes so logind does not also act on KEY_POWER.
    for p in power_devs:
        try:
            p.grab()
        except OSError as err:
            log(f"grab {p.path} ({p.name}) failed: {err}")
            close_quietly([*power_devs, keyd])
            return 1

    power_desc = ", ".join(f"{p.path} ({p.name})" for p in power_devs)
    log(
        f"watching {power_desc} + {keyd.path} ({keyd.name}) "
        f"for user {user}; back={sorted(BACK_CODES)} refresh={sorted(REFRESH_CODES)} "
        f"grace={CHORD_GRACE_SEC}s"
    )

    power_held_fds: set[int] = set()
    power_down_at: float | None = None
    combo_used = False
    last_combo_at = 0.0
    back_held = False
    refresh_held = False
    suspend_cooldown_until = 0.0
    # When set, a short press is pending suspend until this monotonic time
    # (or until a chord arrives / cooldown blocks it).
    pending_suspend_until: float | None = None

    power_fds = {p.fd for p in power_devs}
    devices: dict[int, InputDevice] = {p.fd: p for p in power_devs}
    devices[keyd.fd] = keyd

    def trigger_logout() -> None:
        nonlocal combo_used, last_combo_at, pending_suspend_until
        combo_used = True
        last_combo_at = time.monotonic()
        pending_suspend_until = None
        run(["loginctl", "terminate-user", user])

    def trigger_reboot() -> None:
        nonlocal combo_used, last_combo_at, pending_suspend_until
        combo_used = True
        last_combo_at = time.monotonic()
        pending_suspend_until = None
        run(["systemctl", "reboot"])

    def maybe_chord_from_held() -> None:
        """If Power just went down while Back/F1 or Refresh/F2 already held."""
        if combo_used or power_down_at is None:
            return
        if back_held:
            log("chord: power while Back/F1 held → logout")
            trigger_logout()
        elif refresh_held:
            log("chord: power while Refresh/F2 held → reboot")
            trigger_reboot()

    def arm_pending_suspend() -> None:
        nonlocal pending_suspend_until
        if time.monotonic() < suspend_cooldown_until:
            pending_suspend_until = None
            return
        pending_suspend_until = time.monotonic() + CHORD_GRACE_SEC

    try:
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
                    suspend_cooldown_until = time.monotonic() + SUSPEND_COOLDOWN_SEC
                    power_held_fds.clear()
                    power_down_at = None
                    back_held = False
                    refresh_held = False
                    combo_used = False

            # Long-press poweroff while still held.
            if power_down_at is not None and not combo_used:
                held = now - power_down_at
                if held >= LONG_PRESS_SEC:
                    combo_used = True
                    last_combo_at = now
                    pending_suspend_until = None
                    run(["systemctl", "poweroff"])
                    power_down_at = None
                    power_held_fds.clear()

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

                        if fd in power_fds and code == ecodes.KEY_POWER:
                            event_now = time.monotonic()
                            if key.keystate == 1:
                                was_down = bool(power_held_fds)
                                power_held_fds.add(fd)
                                if not was_down:
                                    if event_now - last_combo_at < COMBO_DEBOUNCE_SEC:
                                        continue
                                    power_down_at = event_now
                                    combo_used = False
                                    pending_suspend_until = None
                                    maybe_chord_from_held()
                            elif key.keystate == 0:
                                power_held_fds.discard(fd)
                                if not power_held_fds:
                                    if power_down_at is not None and not combo_used:
                                        arm_pending_suspend()
                                    power_down_at = None
                                    # Keep combo_used if a chord already fired; otherwise
                                    # clear so the grace window can still accept Back/F1.
                                    if combo_used:
                                        pending_suspend_until = None
                                    else:
                                        combo_used = False
                            continue

                        if dev is keyd:
                            power_or_grace = (
                                power_down_at is not None
                                or pending_suspend_until is not None
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
                                        log("chord: Back/F1 while power/grace → logout")
                                        trigger_logout()
                                else:
                                    back_held = False
                            elif code in REFRESH_CODES:
                                if key.keystate == 1:
                                    refresh_held = True
                                    if power_or_grace and not combo_used:
                                        log("chord: Refresh/F2 while power/grace → reboot")
                                        trigger_reboot()
                                else:
                                    refresh_held = False
                except OSError as err:
                    log(f"read error on {dev.name}: {err}")
                    return 1
    finally:
        close_quietly([*power_devs, keyd])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
