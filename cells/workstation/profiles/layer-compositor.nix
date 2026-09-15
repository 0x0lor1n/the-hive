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
  globals,
  ...
}: let
  theme = inputs.cells.theme.palettes.kanagawa;
  # Per-role encrypted attrset (git includeIf blocks, ssh matchBlocks), PIN
  # identity. Same flakeRoot shape as cells/common/globals.nix.
  userSecrets = role:
    import ../home/secrets.nix {
      flakeRoot = /. + builtins.unsafeDiscardStringContext inputs.self.outPath;
      inherit role;
    };
  mkHome = {
    userName,
    homeDir,
    extraPackages ? [],
    git ? null,
    secrets ? {},
    personal ? false,
  }:
    import ../home {
      inherit userName homeDir theme extraPackages git secrets personal;
      deck = inputs.cells.deck.homeModules;
      agentPkgs = {inherit (inputs.cells.repo.packages) claude-code opencode oh-my-opencode rtk;};
    };

  # The Entra user is an NSS user (himmelblau), not in users.users, so the HM
  # NixOS module can't target it. Build the same home standalone and activate
  # it from a user unit at login. cn = upn before '@', which is also the
  # /home/<cn> alias himmelblau creates (home_alias = "cn" in auth-entra.nix).
  entra = globals.entra.user;
  entraCn = lib.head (lib.splitString "@" entra.upn);
  entraHome = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    # Work-account-only apps live here, not in systemPackages: the local
    # break-glass user has no SSO and no business in the tenant's chat.
    modules = [
      (mkHome {
        userName = entraCn;
        homeDir = "/home/${entraCn}";
        # Sandboxed (packages.nix); state persists via auth-entra.nix.
        extraPackages = [
          cell.packages.slack
          cell.packages.telegram-desktop
        ];
        secrets = userSecrets "entra";
      })
    ];
  };
  # himmelblau creates /home/<upn> and the /home/<cn> alias from pam_himmelblau
  # while the session is opening; the user manager starts home-manager-entra in
  # parallel. On the FIRST login after a boot the home does not exist yet (the
  # root is rolled back, so nothing survives outside /persist) and HM's
  # `activate` dies on its opening `cd $HOME`. Later logins in the same boot
  # find the home already there, which is why this only ever broke right after
  # a reboot. Type=oneshot forbids Restart=, so wait in ExecStartPre instead.
  waitForEntraHome = pkgs.writeShellScript "wait-for-entra-home" ''
    for _ in $(seq 1 120); do
      [ -d "$1" ] && exit 0
      sleep 0.5
    done
    echo "timed out after 60s waiting for $1 (himmelblau did not create it)" >&2
    exit 1
  '';

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
    # A previous dwl session (relogin via greeter) leaves the oneshot bridge
    # active and graphical-session.target up, so a plain `start` is a no-op
    # and avizo/swayidle stay in their start-limit-hit state from the moment
    # the old compositor went away (measured 2026-09-15). Reset + restart
    # re-pulls the target's wants against the new WAYLAND_DISPLAY.
    ${pkgs.systemd}/bin/systemctl --user reset-failed 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user restart dwl-session-bridge.service 2>/dev/null || true

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
    # Last crash log survives in the (persisted) home. Never let the log be
    # the reason the session dies: if $HOME is not there yet (first login
    # after boot raced himmelblaud_tasks), fall back to the journal.
    # Not exec: when dwl exits, take graphical-session.target down with the
    # bridge (BindsTo) so PartOf= units (avizo, swayidle) stop cleanly
    # instead of crash-looping into their start limit.
    if mkdir -p "$HOME/.cache/dwl" 2>/dev/null; then
      ${cell.packages.dwl}/bin/dwl -s ${dwl-startup-with-bar} 2> "$HOME/.cache/dwl/last.log"
    else
      ${cell.packages.dwl}/bin/dwl -s ${dwl-startup-with-bar}
    fi
    rc=$?
    ${pkgs.systemd}/bin/systemctl --user stop dwl-session-bridge.service 2>/dev/null || true
    exit $rc
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
    # The local user holds the checkout: commit identity from public globals.
    home-manager.users.${host.userName} = mkHome {
      inherit (host) userName homeDir;
      git = globals.user.git;
      secrets = userSecrets "local";
      personal = true;
    };

    # HM for the Entra user (see entraHome above). Runs in the user manager
    # PAM starts at login, so dbus is up and dconfSettings works. Idempotent:
    # re-activating the same generation is a no-op.
    #
    # HM's own reloadSystemd step is a no-op here: it gates on
    # `systemctl --user is-system-running` == running|degraded, and a unit
    # wanted by default.target always sees "starting" (measured 2026-09-15:
    # "User systemd daemon not running. Skipping reload" -> tmux-server and
    # ssh-agent linked into default.target.wants but never started, avizo/
    # swayidle the same via graphical-session.target). ExecStartPost does what
    # sd-switch would have: reload so the manager sees the freshly linked
    # ~/.config/systemd/user, then start default.target's wants by hand (the
    # target's job was queued before the links existed, so it will not pull
    # them in itself). graphical-session.target.wants are picked up by the
    # dwl bridge below, which is ordered After= this unit.
    systemd.user.services.home-manager-entra = lib.mkIf (entra.upn != null && entra.uid != null) {
      description = "Home Manager environment for the Entra user";
      unitConfig.ConditionUser = toString entra.uid;
      wantedBy = ["default.target"];
      # activate registers the generation via nix-env, which the unit's
      # default PATH lacks. ~/.local/state/nix/profiles is created by the
      # tmpfiles rules in auth-entra.nix. coreutils: seq/sleep for the wait.
      path = [config.nix.package pkgs.bash pkgs.coreutils pkgs.systemd];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${waitForEntraHome} /home/${entraCn}";
        ExecStart = "${entraHome.activationPackage}/activate";
        ExecStartPost = pkgs.writeShellScript "home-manager-entra-start-wants" ''
          units=${entraHome.activationPackage}/home-files/.config/systemd/user
          systemctl --user daemon-reload
          for u in "$units"/default.target.wants/*; do
            [ -e "$u" ] || continue
            systemctl --user start --no-block "$(basename "$u")" || true
          done
        '';
        TimeoutStartSec = "180s";
      };
    };

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

    # Edge managed policy (ported from ~/nixos-config gui/microsoft-edge.nix,
    # which wrote the same JSON under ~/.config/microsoft-edge/policies --
    # a path Chromium-on-Linux never reads; the system dir is the documented
    # one). Force-installs Dark Reader + Surfingkeys from the Edge Add-ons
    # store for every account.
    environment.etc."opt/edge/policies/managed/extensions.json".text = builtins.toJSON {
      ExtensionInstallForcelist = map (id: "${id};https://edge.microsoft.com/extensionwebstorebase/v1/crx") [
        "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
        "kgnghhfkloifoabeaobjkgagcecbnppg" # Surfingkeys
      ];
    };

    # Known path for greetd's --cmd.
    environment.etc."dwl/session" = {
      source = dwl-session;
      mode = "0755";
    };

    # The sway-session.target pattern: Wants= is allowed to pull in a
    # RefuseManualStart target, BindsTo= ties this unit's lifecycle to it.
    # After=home-manager-entra: graphical-session.target.wants (avizo,
    # swayidle) come from HM's generation; on the local account the unit is
    # skipped by ConditionUser and the ordering is inert.
    systemd.user.services.dwl-session-bridge = {
      description = "DWL session bridge to graphical-session.target";
      unitConfig = {
        BindsTo = ["graphical-session.target"];
        Before = ["graphical-session.target"];
        Wants = ["graphical-session-pre.target" "graphical-session.target"];
        After = ["graphical-session-pre.target" "home-manager-entra.service"];
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
    };
  };
}
