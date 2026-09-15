#!/usr/bin/env bash
# takeshot -- screenshot helper, ported from wochap/nix-config
# (modules/nixos/desktop/wm-addons-wayland/wayland-utils/scripts/takeshot.sh).
#
# Differences from upstream:
#   * colours are baked in from the theme palette at build time instead of
#     sourcing ~/.config/scripts/theme-colors.sh;
#   * runs under writeShellApplication (set -euo pipefail, shellcheck), so
#     the cancel paths (slurp Esc, pgrep miss) are handled explicitly;
#   * PICTURES dir falls back to ~/Pictures when xdg-user-dir is unset.
#
# Usage: takeshot --now | --in5 | --area | --freeze

background="#@theme_bg@"
primary="#@theme_focus@"

time=$(date +%Y-%m-%d_%H-%M-%S)
dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
filename="Screenshot_${time}"
EXPIRE_TIME=5000
grim_dest="$dir/grim_${filename}.png"
dest="$dir/${filename}.webp"

optimize_image() {
  magick "$grim_dest" -quality 85 "$dest"
}

copy_to_cb() {
  printf 'file://%s\n' "$1" | wl-copy -t text/uri-list
}

# Notify with actions. mako has no buttons (see notify.nix): left click =
# default action = edit in satty, middle click = fuzzel menu with all
# three; the 5 s timeout keeps the webp and drops the png.
notify_user() {
  if [[ ! -e $grim_dest ]]; then
    exit 1
  fi

  optimize_image
  copy_to_cb "$dest"

  local thumbnail_size="288x288"
  local thumbnail
  thumbnail=$(mktemp --suffix .png) || exit 1
  trap 'rm -f "$thumbnail"' EXIT
  magick "$grim_dest" -resize "${thumbnail_size}>" -gravity center \
    -background transparent -extent "$thumbnail_size" "$thumbnail"

  local action
  action=$(notify-send --app-name="Takeshot" --expire-time="$EXPIRE_TIME" \
    --replace-id=699 --icon="$thumbnail" \
    "Screen shooter" "Screenshot Saved" \
    --action="default=Edit" --action="open=Open" --action="png=Copy PNG" || true)

  case $action in
  default | edit)
    # satty doesn't support webp
    satty -f "$grim_dest" -o "$dest" &
    ;;
  open)
    rm -f "$grim_dest"
    xdg-open "$dest" &
    ;;
  png)
    copy_to_cb "$grim_dest"
    ;;
  *)
    rm -f "$grim_dest"
    ;;
  esac
}

countdown() {
  local sec
  for sec in $(seq "$1" -1 1); do
    notify-send --app-name="Takeshot" --expire-time=1000 --replace-id=698 \
      --icon="accessories-screenshot" "Taking shot in $sec"
    sleep 1
  done
}

shotnow() {
  grim "$grim_dest"
  notify_user
}

shot5() {
  countdown 5
  sleep 1
  shotnow
}

kill_hyprpicker() {
  pkill -x hyprpicker || true
}

kill_slurp() {
  pkill -x slurp || true
}

# Freeze the screen under slurp (hyprpicker -r: render only, -z: freeze).
freeze_screen() {
  hyprpicker -r -z &
  wait $! || true
  # if hyprpicker is killed, kill slurp too
  kill_slurp
}

shotarea() {
  if pgrep -x slurp >/dev/null; then
    exit 0
  fi
  "$0" --freeze &
  sleep 0.1
  local area
  area=$(slurp -d -b "${background}bf" -c "$primary" -F "monospace" -w 1 || true)
  if [[ -z $area ]]; then
    kill_hyprpicker
    exit 0
  fi
  grim -g "$area" "$grim_dest"
  kill_hyprpicker
  notify_user
}

mkdir -p "$dir"

case ${1:-} in
--now) shotnow ;;
--in5) shot5 ;;
--area) shotarea ;;
--freeze) freeze_screen ;;
*) echo "Available options: --now --in5 --area" ;;
esac
