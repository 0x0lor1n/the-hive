# dwl session, home-manager for every account, portals and the session's user units.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  config,
  globals,
  ...
}: let
  theme = inputs.cells.common.theme;
  # Per-role encrypted attrsets; flakeRoot as in cells/common/globals.nix.
  userSecrets = roles:
    import ../home/secrets.nix {
      flakeRoot = /. + builtins.unsafeDiscardStringContext inputs.self.outPath;
      inherit roles;
    };
  mkHome = {
    userName,
    homeDir,
    roles,
    desktop,
    secrets ? {},
    startDir ? null,
    canonicalHome ? null,
  }:
    import ../home {
      inherit userName homeDir theme roles desktop secrets startDir;
      roleInputs = {
        # nixpak apps bind the account's canonical home, so they are built per account.
        packages =
          cell.packages
          // import ../packages/sandboxed.nix {
            # Cell pkgs, as packages.nix: the host's overlays would rebuild both apps.
            inherit inputs canonicalHome;
            inherit (inputs) pkgs;
            inherit (inputs.pkgs) lib;
          };
        inherit (globals.user) git;
      };
      deck = inputs.cells.deck.homeModules;
      agentPkgs = {
        inherit (inputs.cells.repo.packages) claude-code opencode oh-my-opencode rtk;
        inherit (cell.packages) herdr herdr-integrations;
      };
    };

  # One home per hive.accounts entry (accounts.nix).
  mkAccount = a:
    mkHome {
      userName = a.name;
      homeDir = a.home;
      inherit (a) roles desktop;
      secrets = userSecrets a.roles;
      # $HOME is the /home/<cn> alias; the real directory is /home/<upn>.
      canonicalHome =
        if a.auth == "entra"
        then "/home/${globals.entra.user.upn}"
        else null;
      # tty/ssh/`su -` only; foot lands in tmux, which sesh opens here already.
      startDir =
        if lib.elem "admin" a.roles
        then "/srv/the-hive"
        else null;
    };
  locals = lib.filter (a: a.auth == "local") config.hive.accounts;

  # NSS user, not in users.users: the same home built standalone, activated by a user unit.
  entra = lib.findFirst (a: a.auth == "entra") null config.hive.accounts;
  entraHome = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [(mkAccount entra)];
  };
  # himmelblau creates the home in parallel with the user manager, so on first login after boot
  # HM's activate dies on `cd $HOME`. Type=oneshot forbids Restart=, hence the wait.
  waitForEntraHome = pkgs.writeShellScript "wait-for-entra-home" ''
    for _ in $(seq 1 120); do
      [ -d "$1" ] && exit 0
      sleep 0.5
    done
    echo "timed out after 60s waiting for $1 (himmelblau did not create it)" >&2
    exit 1
  '';

  # Chromium's WebRTC drops PipeWire's VideoTransform, so a rotated output is answered with a
  # wl-mirror window of it (dwl rule: tag 9); xdpw re-reads toplevels (chooser-roundtrip.patch).
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
      # Untiled on hidden tag 9 the mirror stays 100x100; fullscreen sizes it even hidden. -F waits
      # for a wl_surface.enter that never comes, --fullscreen-output refuses the mirrored output.
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

  # "<output> <field> <value>" -> $XDG_RUNTIME_DIR/dwl/<output>/<field>, one dir per waybar
  # (WAYBAR_OUTPUT_NAME); dwl/<field> holds the selected monitor's. bar.nix listens on SIGRTMIN+1.
  dwl-status = pkgs.writeShellScript "dwl-status" ''
    d="''${XDG_RUNTIME_DIR:-/tmp}/dwl"
    mkdir -p "$d"
    sel=""
    last=""
    declare -A layout title mode tags
    # nf-md-pulse (U+F0430), nf-md-transit_connection_variant (U+F0D3D)
    declare -A taglabel=([1]="󰐰" [2]="󰴽")
    render_tags() {
      read -r occ tagset _ urg <<<"$1"
      local i bit l out=""
      for i in 1 2 3 4 5 6 7 8 9; do
        bit=$((1 << (i - 1)))
        l="''${taglabel[$i]:-$i}"
        if (( urg & bit )); then
          out+="<span foreground='#${theme.roles.bg}' background='#${theme.roles.urgent}' weight='bold'> $l </span>"
        elif (( tagset & bit )); then
          out+="<span foreground='#${theme.roles.bg}' background='#${theme.roles.focus}' weight='bold'> $l </span>"
        elif (( occ & bit )); then
          out+="<span foreground='#${theme.roles.fg}'> $l </span>"
        else
          out+="<span foreground='#${theme.roles.muted}'> $l </span>"
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
      # printstatus emits ~8 lines per monitor per event.
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
      # No -x: the wrapped process is named .waybar-wrapped.
      ${pkgs.procps}/bin/pkill -RTMIN+1 waybar 2>/dev/null || true
    done
  '';

  # dwl makes this child's stdin its status pipe, so dwl-status is exec'd to hold it open.
  # mako/swayidle/avizo/waybar are HM units and would run twice if started here.
  dwl-startup-with-bar = pkgs.writeShellScript "dwl-startup-with-bar" ''
    # HM units gate on ConditionEnvironment=WAYLAND_DISPLAY. DISPLAY: X11 apps started by the
    # OpenURI portal (Horizon's sign-in return) would get no display.
    export XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-dwl}"
    ${pkgs.systemd}/bin/systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null || true
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null || true
    # The target refuses manual start, the bridge pulls it. A previous session can leave both
    # up, making `start` a no-op against a dead WAYLAND_DISPLAY: stop first.
    ${pkgs.systemd}/bin/systemctl --user stop graphical-session.target dwl-session-bridge.service 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user reset-failed 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl --user start dwl-session-bridge.service 2>/dev/null || true

    ${pkgs.swaybg}/bin/swaybg -c '#${theme.roles.bg}' &
    ${pkgs.wl-clipboard}/bin/wl-paste --type text  --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store &
    # Tags 1/2 by app_id (packages/dwl/config.h); foot's shell is sesh -> tmux.
    ${pkgs.foot}/bin/foot -a foot-tmux &
    ${pkgs.systemd}/bin/systemctl --user start herdr-server.service 2>/dev/null || true
    ${pkgs.foot}/bin/foot -a foot-herdr ${cell.packages.herdr}/bin/herdr &
    exec ${dwl-status}
  '';

  # greetd's session env is PAM-clean (environment.variables does not reach it), and clients
  # dwl spawns itself inherit only dwl's env.
  dwl-session = pkgs.writeShellScript "dwl-session" ''
    export XDG_CURRENT_DESKTOP=dwl
    export XDG_SESSION_TYPE=wayland
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") config.session.compositorEnvironment)}
    # Without $HOME yet (first Entra login after boot) dwl logs to the journal. Not exec: BindsTo
    # is one-way, PartOf= units would crash-loop into their start limit unless the target stops.
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

  # Hardware profiles put WLR_* here; nothing else reaches the compositor's env.
  options.session.compositorEnvironment = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = {};
    description = "Variables exported to the compositor process only.";
  };

  config = {
    # wlr does screen capture, gtk everything else.
    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-wlr pkgs.xdg-desktop-portal-gtk];
      config.dwl.default = ["wlr" "gtk"];
    };
    # The default slurp only picks outputs; dmenu mode also lists every toplevel.
    xdg.portal.wlr.settings.screencast = {
      chooser_type = "dmenu";
      chooser_cmd = "${share-chooser}/bin/share-chooser";
      exec_after = "${pkgs.procps}/bin/pkill -f 'wl-mirro[r] .*--title Mirror '";
    };

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users = lib.listToAttrs (map (a: lib.nameValuePair a.name (mkAccount a)) locals);

    # HM's reloadSystemd needs is-system-running == running|degraded, which a default.target unit
    # never sees, so ExecStartPost reloads and starts the new default.target wants itself.
    systemd.user.services.home-manager-entra = lib.mkIf (entra != null) {
      description = "Home Manager environment for the Entra user";
      unitConfig.ConditionUser = entra.owner;
      wantedBy = ["default.target"];
      # activate registers the generation via nix-env.
      path = [config.nix.package pkgs.bash pkgs.coreutils pkgs.systemd];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${waitForEntraHome} ${entra.home}";
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

    environment.systemPackages =
      [
        # System package: greetd runs /etc/dwl/session before any HM activation.
        cell.packages.dwl
        # whisper.cpp on Vulkan; parakeet is faster, CPU-only, clean speech only.
        cell.packages.transcribe
        cell.packages.transcribe-parakeet
        pkgs.foot
        # By name from dwl's Super+Alt+H, and the CLI agents drive panes with.
        cell.packages.herdr
        pkgs.fuzzel
        pkgs.swaylock
        pkgs.swaybg
        pkgs.grim
        pkgs.slurp
        pkgs.wl-clipboard
        pkgs.cliphist
        # DPMS toggle for swayidle's 600 s step (vanilla dwl has no dwl-msg).
        pkgs.wlopm
      ]
      # Silent M365 SSO through himmelblau's broker; Entra users get no home.packages profile.
      ++ lib.optional (entra != null) pkgs.microsoft-edge;

    # NixOS module, not home.packages: it also wires xfconf and D-Bus.
    programs.thunar = {
      enable = true;
      plugins = [pkgs.thunar-archive-plugin];
    };
    services.gvfs.enable = true;
    services.udisks2.enable = true;
    services.tumbler.enable = true;

    # Chromium on Linux reads policies only from the system dir. Edge Add-ons ids: Dark Reader's
    # Chrome Web Store id is unknownApplication there and never installs.
    environment.etc."opt/edge/policies/managed/extensions.json".text = builtins.toJSON {
      ExtensionInstallForcelist = map (id: "${id};https://edge.microsoft.com/extensionwebstorebase/v1/crx") [
        "ifoakfbpdcdoeenechcleahebpibofpc" # Dark Reader
        "kgnghhfkloifoabeaobjkgagcecbnppg" # Surfingkeys
      ];
      # Edge sync would reinstall the CWS copy next to the forced one.
      ExtensionInstallBlocklist = ["eimadpbcbfnmbkopoojfekhnkhdbieeh"];
    };

    # Known path for greetd's --cmd.
    environment.etc."dwl/session" = {
      source = dwl-session;
      mode = "0755";
    };

    # sway-session.target pattern. After=home-manager-entra: the target's wants come from its generation.
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

    # Started by dwl-startup-with-bar after import-environment, so panes get WAYLAND_DISPLAY.
    # No PartOf=: agent panes survive a dwl exit.
    systemd.user.services.herdr-server = {
      description = "herdr server (agent sessions)";
      unitConfig = {
        # The server reads config.toml once; HM activation (re)links it.
        After = ["home-manager-entra.service"];
        # The greeter ($HOME=/var/empty) looped on PermissionDenied.
        ConditionUser = "!@system";
      };
      # Pane shells inherit this PATH.
      enableDefaultPath = false;
      serviceConfig = {
        ExecStart = "${cell.packages.herdr}/bin/herdr server";
        Restart = "on-failure";
        RestartSec = "2";
      };
    };
  };
}
