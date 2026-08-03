# Apply or mute max98373 speaker levels on sof-rt5682 (card 0).
# Used at boot, resume, and by the audio-panic alias.
set -u
amixer="${AMIXER:-amixer}"
card="${ALSA_CARD:-0}"

usage() {
  printf 'usage: %s apply|mute\n' "${0##*/}" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage

case "$1" in
apply)
  set +e
  "$amixer" -c "$card" sset 'Left Digital' 80%
  "$amixer" -c "$card" sset 'Right Digital' 80%
  "$amixer" -c "$card" sset 'Left Spk' on
  "$amixer" -c "$card" sset 'Right Spk' on
  "$amixer" -c "$card" sset 'Left Speaker' 8
  "$amixer" -c "$card" sset 'Right Speaker' 8
  true
  ;;
mute)
  set +e
  "$amixer" -c "$card" sset 'Left Digital' 0%
  "$amixer" -c "$card" sset 'Right Digital' 0%
  "$amixer" -c "$card" sset 'Left Spk' off
  "$amixer" -c "$card" sset 'Right Spk' off
  true
  ;;
*)
  usage
  ;;
esac
