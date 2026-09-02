# Compositor layer: DWL + home-manager as a NixOS module. Was test-vm
# profiles/layer-compositor.nix; test-vm's dwl-startup.nix wrote an
# /etc/dwl/startup nothing referenced (the -s target below already does the
# same), so it is not ported.
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
  host,
  ...
}: let
  # DWL 0.8 advertises zwlr_layer_shell_v1 version 3; somebar hardcodes 4 and
  # exits at once without this.
  somebar-patched = pkgs.somebar.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace src/main.cpp \
          --replace-fail \
            'reg.handle(wlrLayerShell, zwlr_layer_shell_v1_interface, 4)' \
            'reg.handle(wlrLayerShell, zwlr_layer_shell_v1_interface, 3)'
      '';
  });

  # Alt+Shift+Return (terminal) never reaches the guest -- the host switches
  # keyboard layouts on Alt+Shift -- so terminal moves to Ctrl+Shift+Return.
  # Adds launcher (Mod+D, was incnmaster), lock (Mod+L, was one of two resize
  # binds), clipboard picker, screenshots and the XF86 volume/brightness keys.
  dwl-custom = pkgs.dwl.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace config.def.h \
          --replace-fail \
            '{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Return,      spawn,            {.v = termcmd} },' \
            '{ WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT,  XKB_KEY_Return,      spawn,            {.v = termcmd} },
             { MODKEY,                              XKB_KEY_v,          spawn,            SHCMD("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy") },
             { MODKEY|WLR_MODIFIER_SHIFT,           XKB_KEY_s,          spawn,            SHCMD("slurp | grim -g - - | wl-copy") },
             { 0,                                   XKB_KEY_Print,      spawn,            SHCMD("grim - | wl-copy") },
             { 0, XKB_KEY_XF86AudioRaiseVolume,  spawn, SHCMD("volumectl -u up") },
             { 0, XKB_KEY_XF86AudioLowerVolume,  spawn, SHCMD("volumectl -u down") },
             { 0, XKB_KEY_XF86AudioMute,         spawn, SHCMD("volumectl toggle-mute") },
             { 0, XKB_KEY_XF86MonBrightnessUp,   spawn, SHCMD("lightctl up") },
             { 0, XKB_KEY_XF86MonBrightnessDown, spawn, SHCMD("lightctl down") },'
        substituteInPlace config.def.h \
          --replace-fail \
            '{ MODKEY,                    XKB_KEY_d,           incnmaster,       {.i = -1} },' \
            '{ MODKEY,                    XKB_KEY_d,           spawn,            SHCMD("fuzzel") },'
        substituteInPlace config.def.h \
          --replace-fail \
            '{ MODKEY,                    XKB_KEY_l,           setmfact,         {.f = +0.05f} },' \
            '{ MODKEY,                    XKB_KEY_l,           spawn,            SHCMD("swaylock -fF") },'
      '';
  });

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

    ${pkgs.swaybg}/bin/swaybg -c '#1e1e2e' &
    ${pkgs.wl-clipboard}/bin/wl-paste --type text  --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store &
    exec ${somebar-patched}/bin/somebar
  '';

  # greetd starts the session with a PAM-clean env (systemd.services.greetd.
  # environment does NOT reach it), and dwl's -s child only exports into the
  # user manager / session bus. Clients spawned by dwl itself (foot, fuzzel)
  # inherit dwl's env, so the desktop identity must be set here, before exec.
  dwl-session = pkgs.writeShellScript "dwl-session" ''
    export XDG_CURRENT_DESKTOP=dwl
    export XDG_SESSION_TYPE=wayland
    exec ${dwl-custom}/bin/dwl -s ${dwl-startup-with-bar}
  '';
in {
  imports = [inputs.home-manager.nixosModules.home-manager];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${host.userName} = import ../home {inherit host;};

  environment.systemPackages = [
    dwl-custom
    somebar-patched
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
}
