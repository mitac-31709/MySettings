# Prefer USB-C sink when a dual-role partner leaves us as source.
#
# delbin's cros_ec_typec advertises preferred_role=source (Try.SRC) and does not
# expose try_role, so power banks often lose negotiation and get charged by the
# Chromebook. Request a PD power-role swap to sink (ChromeOS-like: charge the
# laptop). Intentional accessory charging:
#   echo source | sudo tee /sys/class/typec/port0/power_role
#
# Kernel power_role strings (brackets = current role):
#   "[source] sink"  → we are sourcing (need swap)
#   "source [sink]"  → we are sinking (already OK)

settle_sec="${TYPEC_PREFER_SINK_SETTLE_SEC:-1}"
retries="${TYPEC_PREFER_SINK_RETRIES:-5}"

prefer_sink_once() {
  local partner port role_file current
  shopt -s nullglob
  for partner in /sys/class/typec/port*-partner; do
    port="$(basename "$partner")"
    port="${port%-partner}"
    role_file="/sys/class/typec/${port}/power_role"
    [[ -w $role_file ]] || continue
    current="$(<"$role_file")"
    # TYPEC_SOURCE — Chromebook is charging the partner (e.g. power bank).
    if [[ $current == '[source] sink' ]]; then
      echo "typec ${port}: ${current} → requesting sink"
      if printf 'sink\n' >"$role_file"; then
        echo "typec ${port}: wrote sink (now $(<"$role_file"))"
      else
        echo "typec ${port}: sink write failed (status $?)" >&2
      fi
    else
      echo "typec ${port}: ${current} (no swap)"
    fi
  done
}

for ((i = 0; i < retries; i++)); do
  sleep "$settle_sec"
  prefer_sink_once
done
