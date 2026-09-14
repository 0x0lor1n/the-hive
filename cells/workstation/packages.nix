{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;
  lib = pkgs.lib;
  theme = inputs.cells.theme.palettes.kanagawa;

  # dwl and somebar are C/C++ and cannot import Nix, so their config files
  # carry @theme_<role>@ placeholders that replaceVars fills from the palette.
  # `f` adapts the hex to the language: dwl wants a bare rrggbb inside
  # COLOR(0x...ff), somebar wants "0xrr, 0xgg, 0xbb" for Color(r, g, b).
  # replaceVars fails on an unused variable, so each file names the roles it
  # actually reads.
  themeVars = f: roles: lib.genAttrs (map (r: "theme_${r}") roles) (n: f theme.roles.${lib.removePrefix "theme_" n});
  cxxRgb = hex: lib.concatMapStringsSep ", " (b: "0x${b}") [(builtins.substring 0 2 hex) (builtins.substring 2 2 hex) (builtins.substring 4 2 hex)];

  dwlConfig = pkgs.replaceVars ./packages/dwl/config.h (themeVars lib.id ["bg" "border" "focus" "urgent"]);
  somebarConfig = pkgs.replaceVars ./packages/somebar/config.hpp (themeVars cxxRgb ["bg" "fg" "focus"]);

  mkNixPak = inputs.nixpak.lib.nixpak {inherit (pkgs) lib pkgs;};
  # Desktop apps behind bwrap + xdg-dbus-proxy. An app sees its own state
  # (~/.var/app/<appId>, mapped over the XDG dirs), ~/Downloads, the
  # Wayland/PipeWire sockets and a filtered session bus; nothing else of the
  # home. The Flatpak appId is real, so xdg-desktop-portal treats the app as
  # a Flatpak: file dialogs and link opening go through the portals.
  sandboxed = {
    package,
    appId,
    dbus ? {},
    env ? {},
    extra ? {},
  }:
    (mkNixPak {
      config = {
        imports = [
          ({sloth, ...}: {
            app.package = package;
            flatpak.appId = appId;

            dbus.policies =
              {
                "org.freedesktop.DBus" = "talk";
                "org.freedesktop.portal.Desktop" = "talk";
                "org.freedesktop.portal.Documents" = "talk";
                "org.freedesktop.Notifications" = "talk";
                "org.freedesktop.ScreenSaver" = "talk";
              }
              // dbus;

            gpu.enable = true;
            etc.sslCertificates.enable = true;
            timeZone.enable = true;

            bubblewrap = {
              sockets = {
                wayland = true;
                pipewire = true;
                pulse = true;
              };
              bind.rw = [
                [(sloth.mkdir sloth.appConfigDir) sloth.xdgConfigHome]
                [(sloth.mkdir sloth.appDataDir) sloth.xdgDataHome]
                [(sloth.mkdir sloth.appCacheDir) sloth.xdgCacheHome]
                (sloth.mkdir sloth.xdgDownloadDir)
                # /tmp: bwrap starts from an empty root and nixpak adds none.
                # Chromium/Electron keeps its SingletonSocket there (Qt its
                # lock/IPC files); without it the main process hangs before
                # mapping a window. It must also be the SAME directory for
                # every instance of one app: a URL-handler launch (browser ->
                # slack://) is a second instance that must reach the first
                # over that socket. With a private tmpfs the symlink dangles,
                # the lock's pid is invisible from the new pid namespace, so
                # Chromium treats the lock as stale and opens a second, empty
                # window. Same trick as Flatpak: a per-appId dir under
                # XDG_RUNTIME_DIR (tmpfs, gone at logout, not shared between
                # apps).
                [(sloth.mkdir (sloth.concat' sloth.runtimeDir "/app/${appId}/tmp")) "/tmp"]
              ];
              # Host fontconfig: its <dir> entries are store paths, already bound.
              # os-release: Electron apps (Slack) read it at startup to collect
              # distro info; without it Slack throws "No unique release file
              # found!" in the main process and never creates a window.
              bind.ro = [
                "/etc/fonts"
                ["/etc/static/os-release" "/etc/os-release"]
                ["/etc/static/lsb-release" "/etc/lsb-release"]
              ];
              # xdg-open (Electron/Qt shell out to it for links) picks the
              # flatpak backend by $XDG_RUNTIME_DIR/flatpak-info; nixpak only
              # binds /.flatpak-info, so it falls to "generic", finds no
              # browser on the sandbox PATH and drops the URL (SSO redirect
              # never reaches Edge). NixOS' xdg-utils patch: force the portal
              # (OpenURI), which the dbus policy above already allows.
              env = {NIXOS_XDG_OPEN_USE_PORTAL = "1";} // env;
              newSession = true;
              dieWithParent = true;
            };
          })
          extra
        ];
      };
    }).config.env;

  # Chromium/Electron: the bundled Chromium reads NIXOS_OZONE_WL for Wayland
  # (the wrappers test it), and its own renderer sandbox works under bwrap
  # (nested user namespaces). Screen share goes through the wlr portal.
  chromiumEnv = {
    NIXOS_OZONE_WL = "1";
  };
in {
  # The agenix-rekey CLI from this cell's input, so the deploy shell (which
  # has no such input) ships the same binary the workstation shell does.
  agenix = inputs.agenix-rekey.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # dwl with our config.h. dwl's Makefile copies config.def.h to config.h only
  # when the latter is absent, so dropping the file in is the whole override --
  # no sed patching of upstream. Keybinds and rationale live in packages/dwl/config.h.
  # movestack from codeberg.org/dwl/dwl-patches, config.def.h hunks stripped
  # (our config.h carries the keybinds). Re-fetch on a dwl version bump.
  dwl = pkgs.dwl.overrideAttrs (old: {
    patches =
      (old.patches or [])
      ++ [
        ./packages/dwl/patches/movestack-0.8.patch
        # Keybindings are latin; without this none of them fire while the
        # ru group is active (xkb_state_key_get_syms follows the group).
        ./packages/dwl/patches/latin-keybindings.patch
      ];
    postPatch =
      (old.postPatch or "")
      + ''
        cp ${dwlConfig} config.h
      '';
  });

  # Colors/font in packages/somebar/config.hpp; nixpkgs copies `conf` over
  # src/config.hpp in prePatch.
  # DWL 0.8 advertises zwlr_layer_shell_v1 version 3; somebar hardcodes 4 and
  # exits at once without this.
  somebar = (pkgs.somebar.override {conf = somebarConfig;}).overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace src/main.cpp \
          --replace-fail \
            'reg.handle(wlrLayerShell, zwlr_layer_shell_v1_interface, 4)' \
            'reg.handle(wlrLayerShell, zwlr_layer_shell_v1_interface, 3)'
      '';
  });

  telegram-desktop = sandboxed {
    package = pkgs.telegram-desktop;
    appId = "org.telegram.desktop";
    dbus."org.mpris.MediaPlayer2.tdesktop" = "own";
    env.QT_QPA_PLATFORM = "wayland";
  };

  # nixpkgs' slack rpath has no libva, so Chromium's va_stubs fail to
  # dlopen(libva.so.2) and video decode falls back to software. The dlopen
  # originates in the main binary, so its RUNPATH is what gets searched;
  # libva then finds iHD_drv_video.so via /run/opengl-driver (gpu.enable).
  # libva-minimal is already in the closure through ffmpeg: no extra deps.
  slack = sandboxed {
    package = pkgs.slack.overrideAttrs (old: {
      postFixup =
        (old.postFixup or "")
        + ''
          patchelf --add-rpath ${lib.makeLibraryPath [pkgs.libva-minimal]} $out/lib/slack/slack
        '';
    });
    appId = "com.slack.Slack";
    env = chromiumEnv;
  };
}
