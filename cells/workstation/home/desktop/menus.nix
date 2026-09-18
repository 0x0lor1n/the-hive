# powermenu / calcmenu / wifimenu: fuzzel --dmenu menus (our launcher,
# home/desktop/launcher.nix). The first two are wochap's tofi-powermenu and
# tofi-calc rewritten; wifimenu has no wochap counterpart (he runs impala by
# hand). Bound in packages/dwl/config.h to Super+Esc, Super+C, Super+Alt+W.
#
# powermenu: no uwsm here, so Logout kills the compositor -- dwl-session
# (layer-compositor.nix) then stops graphical-session.target and greetd
# comes back. Lock goes through loginctl so swayidle's lock handler
# (home/desktop/idle.nix) runs the same swaylock as everywhere else.
# No Suspend entry: swayidle still suspends at 1800 s (idle.nix), and the
# menu slot is worth more as the CPU governor flip (profiles/cpu-governor.nix
# declares the units and the polkit rule that makes them password-free).
#
# calcmenu: qalc (libqalculate) instead of bc -- unit-aware, no `scale=`
# dance, and "2^10" means what it says. The result goes to the clipboard
# and, while the popup is open again, the history is offered for reuse.
{pkgs, ...}: let
  powermenu = pkgs.writeShellApplication {
    name = "powermenu";
    runtimeInputs = with pkgs; [fuzzel systemd coreutils libnotify procps];
    text = ''
      # intel_pstate active mode offers exactly performance and powersave.
      gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"
      if [ "$gov" = "performance" ]; then
        next="powersave"
      else
        next="performance"
      fi

      shutdown="  Shutdown"
      reboot="  Reboot"
      cpu="  CPU: $gov → $next"
      logout="  Logout"
      lock="  Lock"

      selected="$(printf '%s\n' "$lock" "$cpu" "$logout" "$reboot" "$shutdown" \
        | fuzzel --dmenu --prompt 'power: ' --lines 5 --width 28)"

      case "$selected" in
        "$shutdown") systemctl poweroff ;;
        "$reboot")   systemctl reboot ;;
        "$logout")   pkill -x dwl ;;
        "$lock")     loginctl lock-session ;;
        "$cpu")
          # oneshot: the unit exits once the governor is written, so --wait
          # to learn whether it actually did. SIGRTMIN+4 refreshes waybar's
          # custom/cpu-governor (home/desktop/bar.nix) instead of leaving it
          # stale until its next poll.
          if systemctl start --wait "cpu-governor@$next.service"; then
            notify-send -a powermenu "CPU governor" "$next"
          else
            notify-send -u critical -a powermenu "CPU governor" "failed to set $next"
          fi
          pkill -RTMIN+4 waybar || true
          ;;
      esac
    '';
  };

  calcmenu = pkgs.writeShellApplication {
    name = "calcmenu";
    runtimeInputs = with pkgs; [fuzzel libqalculate wl-clipboard libnotify coreutils];
    text = ''
      history="''${XDG_CACHE_HOME:-$HOME/.cache}/calcmenu-history"
      touch "$history"

      # Enter on a history line re-evaluates its left-hand side, so a past
      # result can be extended by editing rather than retyped.
      selected="$(fuzzel --dmenu --prompt 'calc: ' --lines 8 --width 40 < "$history")" || exit 0
      [ -n "$selected" ] || exit 0

      input="''${selected%% = *}"
      if ! result="$(qalc -t "$input")"; then
        notify-send -a calcmenu "calc" "cannot evaluate: $input"
        exit 1
      fi

      line="$input = $result"
      { echo "$line"; grep -Fxv -- "$line" "$history"; } | head -n 50 > "$history.tmp"
      mv "$history.tmp" "$history"

      printf '%s' "$result" | wl-copy
      notify-send -a calcmenu "$line" "copied"
    '';
  };
  # wifimenu: NetworkManager front-end in fuzzel. First line is the toggle
  # (radio on/off), then every visible SSID once, strongest BSSID first,
  # marked with the signal and a `*` when connected / `+` when a profile
  # exists. Known network -> `con up` (saved key); new secured network ->
  # a second, masked fuzzel for the passphrase. nmcli's -t output escapes
  # `:` inside fields as `\:`, hence the unescape. Wochap runs impala
  # (iwd) for this; NM here (profiles/laptop.nix), so nmcli.
  wifimenu = pkgs.writeShellApplication {
    name = "wifimenu";
    runtimeInputs = with pkgs; [fuzzel networkmanager libnotify gawk coreutils];
    text = ''
      notify() { notify-send -a wifimenu "$@"; }

      if [ "$(nmcli -t -f WIFI radio)" = "enabled" ]; then
        toggle="  disable wi-fi"
      else
        toggle="  enable wi-fi"
        # Nothing to list while the radio is off; offer the toggle only.
        [ "$(printf '%s\n' "$toggle" | fuzzel --dmenu --prompt 'wi-fi: ' --lines 1 --width 36)" = "$toggle" ] || exit 0
        nmcli radio wifi on
        notify "wi-fi" "enabled"
        exit 0
      fi

      # IN-USE:SSID:SIGNAL:SECURITY, one line per BSSID; nmcli sorts by
      # signal, so the first occurrence of an SSID is its best AP.
      list="$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan auto \
        | sed 's/\\:/\x01/g' \
        | awk -F: '$2 != "" && !seen[$2]++ { printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $4 }' \
        | tr '\001' ':')"
      known="$(nmcli -t -f NAME,TYPE con show | awk -F: '$2 == "802-11-wireless" { print $1 }')"

      menu="$(printf '%s\n' "$toggle"; printf '%s\n' "$list" | while IFS=$'\t' read -r inuse ssid signal sec; do
        mark=" "
        [ "$inuse" = "*" ] && mark="*"
        [ "$mark" = " " ] && grep -Fxq -- "$ssid" <<< "$known" && mark="+"
        lock=" "
        [ -n "$sec" ] && lock=""
        printf '%s %s %3s%%  %s\n' "$mark" "$lock" "$signal" "$ssid"
      done)"

      selected="$(printf '%s\n' "$menu" | fuzzel --dmenu --prompt 'wi-fi: ' --lines 12 --width 40)" || exit 0
      [ -n "$selected" ] || exit 0

      if [ "$selected" = "$toggle" ]; then
        nmcli radio wifi off
        notify "wi-fi" "disabled"
        exit 0
      fi

      # "<mark> <lock> <sig>%  <ssid>": the ssid is everything after the
      # two-space separator, so names with spaces survive.
      ssid="''${selected#*%  }"
      sec="$(printf '%s\n' "$list" | awk -F'\t' -v s="$ssid" '$2 == s { print $4; exit }')"

      if grep -Fxq -- "$ssid" <<< "$known"; then
        if out="$(nmcli con up id "$ssid" 2>&1)"; then
          notify "wi-fi" "connected to $ssid"
        else
          notify -u critical "wi-fi" "$ssid: $out"
        fi
        exit 0
      fi

      args=()
      if [ -n "$sec" ]; then
        pass="$(fuzzel --dmenu --prompt-only "$ssid password: " --password --width 40)" || exit 0
        [ -n "$pass" ] || exit 0
        args=(password "$pass")
      fi
      if out="$(nmcli dev wifi connect "$ssid" "''${args[@]}" 2>&1)"; then
        notify "wi-fi" "connected to $ssid"
      else
        # A wrong passphrase leaves a half-made profile behind that would
        # make the next attempt a silent `con up` failure; drop it.
        nmcli con delete id "$ssid" >/dev/null 2>&1 || true
        notify -u critical "wi-fi" "$ssid: $out"
      fi
    '';
  };
in {
  home.packages = [powermenu calcmenu wifimenu];
}
