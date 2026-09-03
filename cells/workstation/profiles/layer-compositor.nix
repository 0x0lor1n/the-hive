# Compositor layer: DWL + home-manager as a NixOS module. Session startup is
# the `-s` target below; there is deliberately no separate /etc/dwl/startup.
#
# dwl is a SYSTEM package, not home.packages: greetd execs /etc/dwl/session as
# the authenticated user and system packages are on PATH regardless of whether
# HM activation has run in this boot. Same for microsoft-edge: Entra users are
# not local users and never get a home.packages profile.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  config,
  host,
  ...
}: let
  theme = inputs.cells.theme.palettes.kanagawa;
  # `dwl -s <cmd>`: dwl makes the child's stdin the read end of its status
  # pipe, so somebar must be exec'd (not backgrounded) to hold it open. swaybg
  # and the cliphist watchers start here; mako/swayidle/avizo have HM user
  # units and must NOT also be started here.
  dwl-startup-with-bar = pkgs.writeShellScript "dwl-startup-with-bar" ''
    # systemd 257+ refuses `systemctl --user start graphical-session.target`
    # (RefuseManualStart=yes), silently stranding every WantedBy= unit. Start
    # the bridge unit below instead: Wants= may pull the target in.
    #
    # dwl sets WAYLAND_DISPLAY only in its own environment; the HM units
    # (avizo, swayidle) gate on ConditionEnvironment=WAYLAND_DISPLAY, so hand
    # the session variables to the user manager and the session bus first.
    export XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-dwl}"
    ${pkgs.systemd}/bin/systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null || true
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user start dwl-session-bridge.service 2>/dev/null || true

    ${pkgs.swaybg}/bin/swaybg -c '#${theme.roles.bg}' &
    ${pkgs.wl-clipboard}/bin/wl-paste --type text  --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store &
    exec ${cell.packages.somebar}/bin/somebar
  '';

  # greetd starts the session with a PAM-clean env (systemd.services.greetd.
  # environment does NOT reach it, and neither does environment.variables),
  # and dwl's -s child only exports into the user manager / session bus.
  # Clients spawned by dwl itself (foot, fuzzel) inherit dwl's env, so the
  # desktop identity and any wlroots knobs must be set here, before exec.
  dwl-session = pkgs.writeShellScript "dwl-session" ''
    export XDG_CURRENT_DESKTOP=dwl
    export XDG_SESSION_TYPE=wayland
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") config.session.compositorEnvironment)}
    # Last crash log survives in the (persisted) home.
    mkdir -p "$HOME/.cache/dwl"
    exec ${cell.packages.dwl}/bin/dwl -s ${dwl-startup-with-bar} 2> "$HOME/.cache/dwl/last.log"
  '';
in {
  imports = [inputs.home-manager.nixosModules.home-manager];

  # The only channel into the compositor's environment (see dwl-session).
  # Hardware profiles put WLR_* here; UX profiles should not need it.
  options.session.compositorEnvironment = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = {};
    description = "Variables exported to the compositor process only.";
  };

  config = {
    # File pickers, screen sharing (Edge/Teams), xdg-open. wlr does screen
    # capture, gtk everything else.
    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-wlr pkgs.xdg-desktop-portal-gtk];
      config.dwl.default = ["wlr" "gtk"];
    };

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.${host.userName} = import ../home {inherit host theme;};

    environment.systemPackages = [
      cell.packages.dwl
      cell.packages.somebar
      pkgs.foot
      pkgs.fuzzel
      pkgs.swaylock
      pkgs.swaybg
      pkgs.grim
      pkgs.slurp
      pkgs.wl-clipboard
      pkgs.cliphist
      # DPMS toggle for swayidle's 600 s step (vanilla dwl has no dwl-msg).
      pkgs.wlopm
      # Silent M365 SSO through himmelblau's broker DBus service.
      pkgs.microsoft-edge
    ];

    # Known path for greetd's --cmd.
    environment.etc."dwl/session" = {
      source = dwl-session;
      mode = "0755";
    };

    # The sway-session.target pattern: Wants= is allowed to pull in a
    # RefuseManualStart target, BindsTo= ties this unit's lifecycle to it.
    systemd.user.services.dwl-session-bridge = {
      description = "DWL session bridge to graphical-session.target";
      unitConfig = {
        BindsTo = ["graphical-session.target"];
        Before = ["graphical-session.target"];
        Wants = ["graphical-session-pre.target" "graphical-session.target"];
        After = ["graphical-session-pre.target"];
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
    };
  };
}
