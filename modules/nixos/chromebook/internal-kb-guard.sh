# Inhibit the built-in AT Translated Set 2 keyboard while any
# USB/Bluetooth keyboard is present (palm / accidental keypresses).
#
# keyd virtual keyboards and other non-usb/bluetooth buses are ignored.
# Manual re-check: systemctl start chromebook-internal-kb-guard

settle_sec="${INTERNAL_KB_GUARD_SETTLE_SEC:-0.5}"

set_internal_inhibited() {
  local want="$1" namef attr current
  shopt -s nullglob
  for namef in /sys/class/input/input*/name; do
    [[ $(<"$namef") == 'AT Translated Set 2 keyboard' ]] || continue
    attr="$(dirname "$namef")/inhibited"
    [[ -w $attr ]] || continue
    current="$(<"$attr")"
    if [[ $current != "$want" ]]; then
      printf '%s\n' "$want" >"$attr" || true
    fi
  done
}

has_external_keyboard() {
  local ev props bus
  shopt -s nullglob
  for ev in /dev/input/event*; do
    props="$(udevadm info -q property -n "$ev" 2>/dev/null)" || continue
    printf '%s\n' "$props" | grep -qx 'ID_INPUT_KEYBOARD=1' || continue
    bus="$(printf '%s\n' "$props" | sed -n 's/^ID_BUS=//p')"
    case "$bus" in
      usb | bluetooth) return 0 ;;
    esac
  done
  return 1
}

sleep "$settle_sec"

if has_external_keyboard; then
  set_internal_inhibited 1
else
  set_internal_inhibited 0
fi
