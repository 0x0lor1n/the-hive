# waybar: the status bar, replacing somebar. Pieces of wochap's ags/quickshell
# bar that make sense without his dwl fork: no tags (switched by keyboard,
# never clicked), no dwl-ipc patch -- the layout/mode/title come from dwl's
# own `-s` status pipe through dwl-status (profiles/layer-compositor.nix),
# which writes $XDG_RUNTIME_DIR/dwl/<field> and pokes waybar with
# SIGRTMIN+1. Recorder (recorder.nix) pokes SIGRTMIN+2.
#
# Starts as an HM user unit on graphical-session.target, same as mako/
# swayidle/avizo -- the dwl-session-bridge unit pulls it in, do NOT also
# start it from the dwl startup script. Super+B sends SIGUSR1 (toggle).
#
# Modules that read hardware that is not there (coretemp, intel_backlight,
# BAT0 in the VM) fail to construct and waybar logs and skips them.
{
  pkgs,
  lib,
  theme,
  ...
}: let
  k = theme.colors;
  r = theme.roles;

  # `<field>` file written by dwl-status for the selected monitor.
  dwlField = field: json:
    pkgs.writeShellScript "dwl-${field}" ''
      f="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dwl/${field}"
      [ -r "$f" ] || exit 0
      ${json}
    '';
  dwlLayout = dwlField "layout" ''cat "$f"'';
  dwlTitle = dwlField "title" ''cat "$f"'';
  # class = the mode label, so css can colour "layout" and "notification".
  dwlMode = dwlField "mode" ''
    m=$(cat "$f")
    [ -n "$m" ] || exit 0
    printf '{"text":"%s","class":"%s"}\n' "$m" "$m"
  '';

  # `vpn status` (profiles/vpn.nix) prints "<name> <active|inactive>"; the
  # command is absent in the VM, hence the guard.
  vpnStatus = pkgs.writeShellScript "bar-vpn" ''
    command -v vpn >/dev/null || exit 0
    up=$(vpn status | ${pkgs.gawk}/bin/awk '$2 == "active" {print $1}' | paste -sd, -)
    [ -n "$up" ] || exit 0
    printf '{"text":"󰖂 %s","class":"active","tooltip":"vpn up: %s"}\n' "$up" "$up"
  '';

  # mako: dnd mode (invisible=1 in notify.nix) or the number of visible
  # notifications; hidden when neither.
  makoStatus = pkgs.writeShellScript "bar-mako" ''
    if ${pkgs.mako}/bin/makoctl mode | grep -qx dnd; then
      printf '{"text":"󰂛","class":"dnd","tooltip":"do not disturb"}\n'
      exit 0
    fi
    n=$(${pkgs.mako}/bin/makoctl list | ${pkgs.jq}/bin/jq '.data[0] | length')
    [ "$n" -gt 0 ] || exit 0
    printf '{"text":"󰂚 %s","class":"pending","tooltip":"%s notifications"}\n' "$n" "$n"
  '';

  recorderStatus = pkgs.writeShellScript "bar-recorder" ''
    [ "$(recorder --status)" = true ] || exit 0
    printf '{"text":"󰑊 REC","class":"recording","tooltip":"click to stop"}\n'
  '';
in {
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings.bar = {
      layer = "top";
      position = "top";
      height = 26;
      spacing = 8;
      modules-left = ["custom/dwl-layout" "custom/dwl-mode" "custom/recorder"];
      modules-center = ["custom/dwl-title"];
      modules-right = [
        "tray"
        "custom/vpn"
        "custom/notifications"
        "idle_inhibitor"
        "temperature"
        "backlight"
        "pulseaudio"
        "bluetooth"
        "network"
        "battery"
        "clock"
      ];

      "custom/dwl-layout" = {
        exec = dwlLayout;
        interval = "once";
        signal = 1;
        tooltip = false;
      };
      "custom/dwl-mode" = {
        exec = dwlMode;
        return-type = "json";
        interval = "once";
        signal = 1;
        format = "[{}]";
        tooltip = false;
      };
      "custom/dwl-title" = {
        exec = dwlTitle;
        interval = "once";
        signal = 1;
        max-length = 80;
        tooltip = false;
      };
      "custom/recorder" = {
        exec = recorderStatus;
        return-type = "json";
        interval = "once";
        signal = 2;
        on-click = "recorder --area";
      };

      tray = {
        spacing = 8;
        icon-size = 16;
      };
      "custom/vpn" = {
        exec = vpnStatus;
        return-type = "json";
        interval = 10;
      };
      "custom/notifications" = {
        exec = makoStatus;
        return-type = "json";
        interval = 5;
        signal = 3;
        on-click = "${pkgs.mako}/bin/makoctl mode -t dnd && pkill -RTMIN+3 waybar";
        on-click-right = "${pkgs.mako}/bin/makoctl dismiss --all && pkill -RTMIN+3 waybar";
      };
      idle_inhibitor = {
        format = "{icon}";
        format-icons = {
          activated = "󰅶";
          deactivated = "󰾪";
        };
        tooltip-format-activated = "idle inhibited";
        tooltip-format-deactivated = "idle: swayidle may lock";
      };
      temperature = {
        hwmon-path-abs = "/sys/devices/platform/coretemp.0/hwmon";
        input-filename = "temp1_input";
        critical-threshold = 85;
        interval = 5;
        format = "{icon} {temperatureC}°";
        format-icons = ["󱃃" "󰔏" "󱃂"];
      };
      backlight = {
        device = "intel_backlight";
        format = "{icon} {percent}%";
        format-icons = ["󰃞" "󰃟" "󰃠"];
        on-scroll-up = "${pkgs.avizo}/bin/lightctl up";
        on-scroll-down = "${pkgs.avizo}/bin/lightctl down";
      };
      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 {volume}%";
        format-bluetooth = "{icon}󰂯 {volume}%";
        format-icons.default = ["󰕿" "󰖀" "󰕾"];
        on-click = "${pkgs.avizo}/bin/volumectl toggle-mute";
        on-click-right = "${pkgs.pwvucontrol}/bin/pwvucontrol";
        on-scroll-up = "${pkgs.avizo}/bin/volumectl -u up";
        on-scroll-down = "${pkgs.avizo}/bin/volumectl -u down";
      };
      bluetooth = {
        format = "";
        format-on = "󰂯";
        format-connected = "󰂱 {num_connections}";
        format-disabled = "";
        tooltip-format-connected = "{device_enumerate}";
        on-click = "${pkgs.bluetui}/bin/bluetui";
      };
      network = {
        format-wifi = "󰤨 {essid}";
        format-ethernet = "󰈀 {ifname}";
        format-disconnected = "󰤭";
        tooltip-format = "{ifname} {ipaddr}/{cidr} via {gwaddr}";
        tooltip-format-wifi = "{essid} {signalStrength}% {ipaddr}";
        on-click = "wifimenu";
      };
      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-plugged = "󰚥 {capacity}%";
        format-icons = ["󰁺" "󰁼" "󰁾" "󰂀" "󰁹"];
      };
      clock = {
        format = "{:%a %d %b  %H:%M}";
        tooltip-format = "<tt>{calendar}</tt>";
        calendar.format.today = "<b><u>{}</u></b>";
      };
    };

    # GTK CSS. Same palette as foot/fuzzel/mako; font via fontconfig's
    # monospace alias (gtk.nix pins it to JetBrainsMono Nerd Font, which is
    # where the glyphs above come from).
    style = ''
      * {
        font-family: monospace;
        font-size: 11px;
        min-height: 0;
        border: none;
        border-radius: 0;
      }
      window#waybar {
        background: #${r.bg};
        color: #${r.fg};
        border-bottom: 2px solid #${r.border};
      }
      .modules-left, .modules-center, .modules-right { margin: 0 6px; }
      #custom-dwl-layout, #custom-dwl-mode, #custom-dwl-title, #custom-recorder,
      #tray, #custom-vpn, #custom-notifications, #idle_inhibitor, #temperature,
      #backlight, #pulseaudio, #bluetooth, #network, #battery, #clock {
        padding: 0 6px;
      }
      #custom-dwl-layout { color: #${r.focus}; }
      #custom-dwl-mode { color: #${r.bg}; background: #${r.highlight}; font-weight: bold; }
      #custom-dwl-mode.notification { background: #${r.hover}; }
      #custom-dwl-title { color: #${r.muted}; }
      #custom-recorder.recording { color: #${r.bg}; background: #${r.urgent}; font-weight: bold; }
      #custom-vpn.active { color: #${r.accent}; }
      #custom-notifications.dnd { color: #${r.muted}; }
      #custom-notifications.pending { color: #${r.highlight}; }
      #idle_inhibitor.activated { color: #${r.highlight}; }
      #temperature.critical { color: #${r.urgent}; }
      #pulseaudio.muted { color: #${r.muted}; }
      #bluetooth.connected { color: #${r.focus}; }
      #network.disconnected { color: #${r.urgent}; }
      #battery.warning { color: #${r.highlight}; }
      #battery.critical:not(.charging) { color: #${r.urgent}; }
      #clock { color: #${k.fujiWhite}; }
      #tray > .passive { -gtk-icon-effect: dim; }
      #tray > .needs-attention { -gtk-icon-effect: highlight; }
      tooltip { background: #${r.bgAlt}; border: 2px solid #${r.focus}; }
      tooltip label { color: #${r.fg}; }
    '';
  };

  # The user unit gates on WAYLAND_DISPLAY like avizo/swayidle (the HM module
  # sets ConditionEnvironment; the bridge imports the variable). recorder /
  # wifimenu / vpn come from home.packages / systemPackages, which the user
  # manager's PATH does not include by default.
  systemd.user.services.waybar.Service.Environment = ["PATH=/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin"];

  home.packages = [pkgs.bluetui pkgs.pwvucontrol];
}
