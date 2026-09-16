#!/usr/bin/env bash
# recorder: screen recording with wl-screenrec -> ~/Videos/Recordings/*.mp4.
# Ported from wochap/nix-config wayland-utils/scripts/recorder.sh minus the
# hyprctl screen_shader dance (no such thing under dwl).
#
#   recorder --now | --in5 | --area     start (or stop, if one is running)
#   recorder --status                   "true"/"false": is a recording active
#   recorder --listen                   same, re-printed on every change
#
# One recording at a time: $stopfile holds the wl-screenrec pid while it
# runs, so a second invocation from the same keybind stops the first (SIGINT
# lets wl-screenrec finalize the mp4). The bar polls --status.

stopfile="${XDG_RUNTIME_DIR:-/tmp}/recorder.pid"
time=$(date +%Y-%m-%d_%H-%M-%S)
dir="$(xdg-user-dir VIDEOS)/Recordings"
file="Recording_${time}.mp4"
dest="$dir/$file"

trap 'exit 130' INT
trap 'exit 143' TERM

print_status() {
  if [[ -f $stopfile ]]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

listen_status() {
  print_status
  inotifywait -m -q -e create -e delete --format '%f' "$(dirname "$stopfile")" 2>/dev/null |
    while IFS= read -r event_file; do
      if [[ $event_file == "$(basename "$stopfile")" ]]; then
        print_status
      fi
    done
}

wait_recording() {
  local pid=$!
  echo "$pid" >"$stopfile"
  poke_bar
  wait "$pid"
  rm -f "$stopfile"
  poke_bar
}

# bar.nix custom/recorder: interval=once, signal=2. Process is
# `.waybar-wrapped` under nixpkgs, so no -x.
poke_bar() {
  pkill -RTMIN+2 waybar 2>/dev/null || true
}

copy_to_cb() {
  printf 'file://%s\n' "$dest" | wl-copy -t text/uri-list
}

notify_user() {
  [[ -e $dest ]] || exit 1

  copy_to_cb

  local thumbnail
  thumbnail=$(mktemp --suffix .png) || exit 1
  # shellcheck disable=SC2064
  trap "rm -f '$thumbnail'" EXIT
  ffmpegthumbnailer -i "$dest" -o "$thumbnail" -s 500
  magick "$thumbnail" -resize "288x288>" -gravity center -background transparent -extent "288x288" "$thumbnail"

  local action
  action=$(notify-send --app-name="Recorder" --icon="$thumbnail" \
    "Video recording" "Recording saved" \
    --action="open=Open" --action="open_in_fm=Open in file manager")
  case $action in
  open_in_fm) xdg-open "$dir" & ;;
  open) xdg-open "$dest" & ;;
  esac
}

countdown() {
  for sec in $(seq "$1" -1 1); do
    notify-send --app-name="Recorder" --expire-time=1000 --hint=int:transient:1 "Recording in $sec"
    sleep 1
  done
}

shotnow() {
  # Simple command in the background. `cd "$dir" && wl-screenrec ... &`
  # forks a subshell: $! is the subshell (bash makes it ignore SIGINT) and
  # the stop signal never reached wl-screenrec.
  wl-screenrec -f "$dest" &
  wait_recording
  notify_user
}

shot5() {
  countdown 5
  sleep 1
  shotnow
}

shotarea() {
  if pgrep -x slurp >/dev/null; then
    exit 0
  fi
  local area
  area=$(slurp -d -b "#@theme_bg@bf" -c "#@theme_focus@" -w 2)
  [[ -n $area ]] || exit 0
  wl-screenrec -g "$area" -f "$dest" &
  wait_recording
  notify_user
}

mkdir -p "$dir"

# Status queries must not toggle anything.
case "${1:-}" in
--status)
  print_status
  exit 0
  ;;
--listen)
  listen_status
  exit 0
  ;;
esac

# A recording is active: stop it and leave.
if [[ -f $stopfile ]]; then
  pid=$(cat "$stopfile")
  if kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid"
    exit 0
  fi
  rm -f "$stopfile"
fi

case "${1:-}" in
--now) shotnow ;;
--in5) shot5 ;;
--area) shotarea ;;
*)
  echo "usage: recorder --now | --in5 | --area | --status | --listen" >&2
  exit 2
  ;;
esac
