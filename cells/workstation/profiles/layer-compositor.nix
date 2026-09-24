# Compositor layer: DWL + home-manager as a NixOS module. Session startup is
# the `-s` target below; there is no separate /etc/dwl/startup.
#
# dwl is a system package, not home.packages: greetd execs /etc/dwl/session as
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
    startDir ? null,
    httpsHandler ? "firefox.desktop",
  }:
    import ../home {
      inherit userName homeDir theme extraPackages git secrets personal startDir httpsHandler;
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
          # One account only: fixed /tmp launch symlinks (nixpkgs#415842).
          cell.packages.grayjay
          # Horizon behind a gm-only sign-in browser (packages.nix).
          cell.packages.horizon-gm
        ];
        secrets = userSecrets "entra";
        # SharePoint/Word/Excel/PowerPoint links open in the o365 app, the
        # rest fall through to Firefox. Entra only: the local account has no
        # SSO and would get a login wall. See auth-entra.nix.
        httpsHandler = "o365-url-handler.desktop";
      })
    ];
  };
  # himmelblau creates /home/<upn> and the /home/<cn> alias from pam_himmelblau
  # while the session is opening, in parallel with the user manager starting
  # home-manager-entra. On the first login after a boot the home does not exist
  # yet (rolled-back root) and HM's `activate` dies on its opening `cd $HOME`.
  # Type=oneshot forbids Restart=, so wait in ExecStartPre instead.
  waitForEntraHome = pkgs.writeShellScript "wait-for-entra-home" ''
    for _ in $(seq 1 120); do
      [ -d "$1" ] && exit 0
      sleep 0.5
    done
    echo "timed out after 60s waiting for $1 (himmelblau did not create it)" >&2
    exit 1
  '';

  # xdpw chooser (dmenu mode: "Monitor: <out> <desc>" / "Window: <title> (<id>)"
  # lines on stdin). Chromium's WebRTC drops PipeWire's VideoTransform meta,
  # so a rotated output reaches Teams sideways. For those, open a wl-mirror
  # of the output (dwl rule: tag 9, still capturable) and answer with that
  # window instead; xdpw re-reads toplevels first (chooser-roundtrip.patch).
  share-chooser = pkgs.writeShellApplication {
    name = "share-chooser";
    runtimeInputs = with pkgs; [fuzzel wl-mirror wlr-randr lswt jq util-linux coreutils];
    text = ''
      sel=$(fuzzel --dmenu --lines 10 --width 60 --prompt 'Share: ') || exit 0
      case "$sel" in
        "Monitor: "*) ;;
        *) printf '%s\n' "$sel"; exit 0 ;;
      esac
      out=''${sel#Monitor: }
      out=''${out%% *}
      transform=$(wlr-randr --json | jq -r --arg o "$out" '.[] | select(.name == $o) | .transform // "normal"')
      # The mirror maps straight onto hidden tag 9, where dwl never tiles it,
      # so it keeps wl-mirror's 100x100 and Teams upscales mush. Fullscreen
      # makes dwl size it to the monitor even hidden. -F waits for a
      # wl_surface.enter that a hidden window never gets, and
      # --fullscreen-output refuses the mirrored output: name another one
      # (dwl sizes to the client's own monitor regardless).
      other=$(wlr-randr --json | jq -r --arg o "$out" '[.[] | select(.enabled and .name != $o) | .name][0] // empty')
      if [ "$transform" = normal ] || [ -z "$other" ]; then
        printf '%s\n' "$sel"
        exit 0
      fi
      title="Mirror $out"
      mirror_id() {
        lswt -j | jq -r --arg t "$title" \
          '.toplevels[] | select(."app-id" == "at.yrlf.wl_mirror" and .title == $t) | .identifier' | head -n1
      }
      id=$(mirror_id)
      if [ -z "$id" ]; then
        setsid -f wl-mirror --fullscreen-output "$other" --title "$title" "$out" </dev/null >/dev/null 2>&1
        for _ in $(seq 50); do
          id=$(mirror_id)
          [ -n "$id" ] && break
          sleep 0.1
        done
      fi
      # No mirror after 5 s: share the output as is (sideways, but working).
      if [ -z "$id" ]; then
        printf '%s\n' "$sel"
      else
        printf 'Window: %s (%s)\n' "$title" "$id"
      fi
    '';
  };

  # `dwl -s <cmd>`: dwl makes the child's stdin the read end of its status
  # pipe, so dwl-status must be exec'd (not backgrounded) to hold it open or
  # the bar shows stale text. swaybg and the cliphist watchers start here;
  # mako/swayidle/avizo/waybar have HM user units and must not also start here.
  #
  # dwl-status: the somebar replacement's back half. Lines are
  # "<output> <field> <value...>" (title/appid/fullscreen/floating/selmon/
  # tags/layout, plus "mode" from the modes patch). State is kept per output in
  # $XDG_RUNTIME_DIR/dwl/<output>/<field>: waybar runs one bar per output and
  # exports WAYBAR_OUTPUT_NAME to every custom exec, so each bar shows its own
  # monitor — without this every bar showed the selected monitor's tags and
  # only redrew on focus change (2026-09-16, two-monitor work profile). The
  # selected monitor's copy stays in $XDG_RUNTIME_DIR/dwl/<field> as fallback.
  # Waybar's custom/dwl-* modules are poked via signal 1 -> SIGRTMIN+1
  # (home/desktop/bar.nix). tags is pango markup: "tags <occ> <tagset> <sel>
  # <urg>" are bitmasks.
  dwl-status = pkgs.writeShellScript "dwl-status" ''
    d="''${XDG_RUNTIME_DIR:-/tmp}/dwl"
    mkdir -p "$d"
    sel=""
    last=""
    declare -A layout title mode tags
    render_tags() {
      read -r occ tagset _ urg <<<"$1"
      local i bit out=""
      for i in 1 2 3 4 5 6 7 8 9; do
        bit=$((1 << (i - 1)))
        if (( urg & bit )); then
          out+="<span foreground='#${theme.roles.bg}' background='#${theme.roles.urgent}' weight='bold'> $i </span>"
        elif (( tagset & bit )); then
          out+="<span foreground='#${theme.roles.bg}' background='#${theme.roles.focus}' weight='bold'> $i </span>"
        elif (( occ & bit )); then
          out+="<span foreground='#${theme.roles.fg}'> $i </span>"
        else
          out+="<span foreground='#${theme.roles.muted}'> $i </span>"
        fi
      done
      printf '%s' "$out"
    }
    while read -r out field rest; do
      case "$field" in
        selmon) [ "$rest" = 1 ] && sel="$out" ;;
        tags) tags["$out"]="$(render_tags "$rest")" ;;
        layout) layout["$out"]="$rest" ;;
        title) title["$out"]="$rest" ;;
        mode) mode["$out"]="$rest" ;;
        *) continue ;;
      esac
      # printstatus emits ~8 lines per monitor per event; write and signal
      # once per actual change, not once per line.
      cur="$sel"
      for o in "''${!tags[@]}"; do
        cur+=$'\n'"$o"$'\n'"''${tags[$o]-}"$'\n'"''${layout[$o]-}"$'\n'"''${title[$o]-}"$'\n'"''${mode[$o]-}"
      done
      [ "$cur" != "$last" ] || continue
      last="$cur"
      for o in "''${!tags[@]}"; do
        mkdir -p "$d/$o"
        printf '%s\n' "''${tags[$o]-}" > "$d/$o/tags"
        printf '%s\n' "''${layout[$o]-}" > "$d/$o/layout"
        printf '%s\n' "''${title[$o]-}" > "$d/$o/title"
        printf '%s\n' "''${mode[$o]-}" > "$d/$o/mode"
      done
      if [ -n "$sel" ]; then
        printf '%s\n' "''${tags[$sel]-}" > "$d/tags"
        printf '%s\n' "''${layout[$sel]-}" > "$d/layout"
        printf '%s\n' "''${title[$sel]-}" > "$d/title"
        printf '%s\n' "''${mode[$sel]-}" > "$d/mode"
      fi
      # nixpkgs wraps the binary: the process is named `.waybar-wrapped`, so
      # `pkill -x waybar` never matched and the bar stayed on tag 1
      # (2026-09-15). Match the comm without -x.
      ${pkgs.procps}/bin/pkill -RTMIN+1 waybar 2>/dev/null || true
    done
  '';

  dwl-startup-with-bar = pkgs.writeShellScript "dwl-startup-with-bar" ''
    # systemd 257+ refuses `systemctl --user start graphical-session.target`
    # (RefuseManualStart=yes), silently stranding every WantedBy= unit. Start
    # the bridge unit below instead: Wants= may pull the target in.
    #
    # dwl sets WAYLAND_DISPLAY only in its own environment; the HM units
    # (avizo, swayidle) gate on ConditionEnvironment=WAYLAND_DISPLAY, so hand
    # the session variables to the user manager and the session bus first.
    # DISPLAY too (dwl sets it for Xwayland before running this): links the
    # OpenURI portal hands to an X11-only app would otherwise start it with no
    # display, and it dies before drawing (Horizon's sign-in return, 2026-09-24).
    export XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-dwl}"
    ${pkgs.systemd}/bin/systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null || true
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null || true
    # A previous dwl session (relogin via greeter) can leave the oneshot bridge
    # active and graphical-session.target up, so a plain `start` is a no-op and
    # avizo/swayidle stay dead from the moment the old compositor went away
    # (measured 2026-09-15). Take the target down first, then start the bridge:
    # its Wants= re-pulls the target and every WantedBy= unit against the new
    # WAYLAND_DISPLAY.
    ${pkgs.systemd}/bin/systemctl --user stop graphical-session.target dwl-session-bridge.service 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user reset-failed 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user start dwl-session-bridge.service 2>/dev/null || true

    ${pkgs.swaybg}/bin/swaybg -c '#${theme.roles.bg}' &
    ${pkgs.wl-clipboard}/bin/wl-paste --type text  --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store &
    exec ${dwl-status}
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
    # Last crash log survives in the (persisted) home; if $HOME is not there
    # yet (first login after boot raced himmelblaud_tasks), fall back to the
    # journal rather than letting the log kill the session.
    # Not exec: when dwl exits, stop graphical-session.target itself so PartOf=
    # units (avizo, swayidle) stop cleanly instead of crash-looping into their
    # start limit. BindsTo is one-way — stopping the bridge does not stop the
    # target (2026-09-15: MOD+Shift+Q left the target active and both units in
    # start-limit-hit).
    if mkdir -p "$HOME/.cache/dwl" 2>/dev/null; then
      ${cell.packages.dwl}/bin/dwl -s ${dwl-startup-with-bar} 2> "$HOME/.cache/dwl/last.log"
    else
      ${cell.packages.dwl}/bin/dwl -s ${dwl-startup-with-bar}
    fi
    rc=$?
    ${pkgs.systemd}/bin/systemctl --user stop graphical-session.target dwl-session-bridge.service 2>/dev/null || true
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
    # slurp (xdpw's first default chooser) only picks outputs. dmenu mode
    # lists outputs and every toplevel (all tags) from ext-foreign-toplevel-list.
    # share-chooser swaps a rotated output for a mirror window; exec_after
    # closes the mirrors once the last screencast ends.
    xdg.portal.wlr.settings.screencast = {
      chooser_type = "dmenu";
      chooser_cmd = "${share-chooser}/bin/share-chooser";
      exec_after = "${pkgs.procps}/bin/pkill -f 'wl-mirro[r] .*--title Mirror '";
    };

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    # The local user holds the checkout: commit identity from public globals.
    home-manager.users.${host.userName} = mkHome {
      inherit (host) userName homeDir;
      git = globals.user.git;
      secrets = userSecrets "local";
      personal = true;
      # This account exists to rebuild the fleet; the checkout is where it
      # works. Only reached by tty/ssh/`su -` -- foot lands in tmux, which
      # sesh already opens at the same path.
      startDir = "/srv/the-hive";
    };

    # HM for the Entra user (see entraHome above). Runs in the user manager
    # PAM starts at login, so dbus is up and dconfSettings works. Idempotent.
    #
    # HM's own reloadSystemd step is a no-op here: it gates on
    # `systemctl --user is-system-running` == running|degraded, and a unit
    # wanted by default.target always sees "starting" (2026-09-15: tmux-server
    # and ssh-agent linked into default.target.wants but never started).
    # ExecStartPost does what sd-switch would have: reload so the manager sees
    # the freshly linked ~/.config/systemd/user, then start default.target's
    # wants by hand — the target's job was queued before the links existed.
    # graphical-session.target.wants are picked up by the dwl bridge below,
    # ordered After= this unit.
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
      # `transcribe <file>`: whisper.cpp on the iGPU (Vulkan), CPU fallbacks.
      # `transcribe-parakeet`: faster, CPU-only, clean speech only.
      cell.packages.transcribe
      cell.packages.transcribe-parakeet
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

    # File manager (Super+Alt+F in packages/dwl/config.h). System-level rather
    # than home.packages: the NixOS module also wires xfconf (settings persist)
    # and the D-Bus bits; gvfs gives it trash://, mtp/smb and the
    # removable-drive sidebar, udisks2 lets it mount them.
    programs.thunar = {
      enable = true;
      plugins = [pkgs.thunar-archive-plugin];
    };
    services.gvfs.enable = true;
    services.udisks2.enable = true;
    # Thumbnails in Thunar (tumbler is what gvfs/thunar ask over D-Bus).
    services.tumbler.enable = true;

    # Edge managed policy: Chromium-on-Linux never reads
    # ~/.config/microsoft-edge/policies, only the system dir. Force-installs
    # Dark Reader + Surfingkeys from the Edge Add-ons store for every account.
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
