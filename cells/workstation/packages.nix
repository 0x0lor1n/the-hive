{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;
  lib = pkgs.lib;
  theme = inputs.cells.theme.palettes.kanagawa;

  # dwl is C and cannot import Nix, so config.h carries @theme_<role>@
  # placeholders that replaceVars fills from the palette (bare rrggbb inside
  # COLOR(0x...ff)). replaceVars fails on an unused variable, so the list
  # names the roles the file actually reads.
  themeVars = roles: lib.genAttrs (map (r: "theme_${r}") roles) (n: theme.roles.${lib.removePrefix "theme_" n});

  dwlConfig = pkgs.replaceVars ./packages/dwl/config.h (themeVars ["bg" "border" "focus" "urgent"]);

  # Mesa's ANV keeps fp16 and DP4a on Gen12, which the q5_0 matmuls need: 11.8s
  # against the CPU's 90.2s to encode 98s of audio.
  whisperCppVulkan = pkgs.whisper-cpp.override {vulkanSupport = true;};

  mkNixPak = inputs.nixpak.lib.nixpak {inherit (pkgs) lib pkgs;};
  # $HOME is the /home/<cn> alias himmelblau creates (auth-entra.nix); the
  # real directory is /home/<upn>. Anything that canonicalises before handing
  # a path over (GIO: Thunar's cwd, hence drag-and-drop URIs) names
  # /home/<upn>, which doesn't exist in the sandbox: bwrap mounts $HOME/...
  # as a plain directory tree, the alias is no symlink inside. null when not
  # an Entra box.
  entraUpn = inputs.cells.common.globals.entra.user.upn;
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
    # Webcam for calls. Microphone needs nothing extra: it already comes
    # through the pipewire/pulse sockets below.
    camera ? false,
    extra ? {},
  }:
    (mkNixPak {
      config = {
        imports = [
          ({sloth, ...}: let
            # [src dst]: same host dir as the $HOME bind, at the canonical name.
            alsoCanonical = sub:
              lib.optional (entraUpn != null)
              [(sloth.mkdir (sloth.concat' sloth.homeDir sub)) "/home/${entraUpn}${sub}"];
          in {
            app.package = package;
            flatpak.appId = appId;

            dbus.policies =
              {
                "org.freedesktop.DBus" = "talk";
                "org.freedesktop.portal.Desktop" = "talk";
                "org.freedesktop.portal.Documents" = "talk";
                "org.freedesktop.Notifications" = "talk";
                "org.freedesktop.ScreenSaver" = "talk";
                # Tray icons (StatusNotifierItem): the app calls
                # RegisterStatusNotifierItem on waybar's watcher and exports
                # /StatusNotifierItem on its own unique bus name (Chromium/Qt
                # both do; no well-known name to `own`). Without the watcher
                # in the proxy policy the call never leaves the sandbox and
                # the icon just doesn't appear.
                "org.kde.StatusNotifierWatcher" = "talk";
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
              bind.rw =
                [
                  [(sloth.mkdir sloth.appConfigDir) sloth.xdgConfigHome]
                  [(sloth.mkdir sloth.appDataDir) sloth.xdgDataHome]
                  [(sloth.mkdir sloth.appCacheDir) sloth.xdgCacheHome]
                  (sloth.mkdir sloth.xdgDownloadDir)
                  # Same dir under /home/<upn> (see entraUpn). Assumes the
                  # default ~/Downloads: there is no user-dirs.dirs.
                  # /tmp: bwrap starts from an empty root and nixpak adds none.
                  # Chromium/Electron keeps its SingletonSocket there (Qt its
                  # lock/IPC files); without it the main process hangs before
                  # mapping a window. It must be the same directory for every
                  # instance of one app: a URL-handler launch (browser ->
                  # slack://) is a second instance that must reach the first
                  # over that socket. With a private tmpfs the symlink dangles
                  # and the lock's pid is invisible from the new pid namespace,
                  # so Chromium treats it as stale and opens a second, empty
                  # window. A per-appId dir under XDG_RUNTIME_DIR, as Flatpak
                  # does it.
                  [(sloth.mkdir (sloth.concat' sloth.runtimeDir "/app/${appId}/tmp")) "/tmp"]
                  # Document portal: for a caller with an app id the FileChooser
                  # portal doesn't return the real path but registers the pick
                  # and hands back $XDG_RUNTIME_DIR/doc/<id>/<name>. Mount the
                  # per-app FUSE view there, as Flatpak does; the portal
                  # synthesizes by-app/<appId> for any id, so the source always
                  # exists. rw: the same path is used for "save as".
                  [(sloth.concat' sloth.runtimeDir "/doc/by-app/${appId}") (sloth.concat' sloth.runtimeDir "/doc")]
                ]
                ++ alsoCanonical "/Downloads";
              # Host fontconfig: its <dir> entries are store paths, already bound.
              # os-release: Electron apps (Slack) read it at startup to collect
              # distro info; without it Slack throws "No unique release file
              # found!" in the main process and never creates a window.
              bind.ro =
                [
                  "/etc/fonts"
                  ["/etc/static/os-release" "/etc/os-release"]
                  ["/etc/static/lsb-release" "/etc/lsb-release"]
                  # Things one attaches to a chat. Chromium reads the file
                  # itself (drag-and-drop passes a plain path; the portal
                  # dialog goes through the doc mount above) -- unreadable
                  # => empty MIME => "not supported".
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/Recordings"))
                  (sloth.mkdir (sloth.concat' sloth.homeDir "/Screenshots"))
                ]
                ++ alsoCanonical "/Recordings"
                ++ alsoCanonical "/Screenshots"
                # Chromium enumerates cameras by scanning /dev/video* and
                # reads the display name from /sys/class/video4linux/<dev>/
                # (the symlink target under /sys/devices/pci0000:00 is
                # already bound by gpu.enable); libudev reads /run/udev.
                ++ lib.optionals camera ["/sys/class/video4linux" "/run/udev"];
              # --dev-bind-try: a missing node (no webcam) is skipped, not
              # fatal. Access is the seat ACL logind puts on the nodes.
              bind.dev = lib.optionals camera ["/dev/video0" "/dev/video1" "/dev/video2" "/dev/video3" "/dev/media0"];
              # xdg-open (Electron/Qt shell out to it for links) picks the
              # flatpak backend by $XDG_RUNTIME_DIR/flatpak-info; nixpak only
              # binds /.flatpak-info, so it falls to "generic", finds no
              # browser on the sandbox PATH and drops the URL (SSO redirect
              # never reaches Edge). NixOS' xdg-utils patch: force the portal
              # (OpenURI), which the dbus policy above already allows.
              # Chromium resolves file types via xdg-mime
              # ($XDG_DATA_DIRS/mime/globs2). bwrap starts with an empty env
              # and no /usr/share, so every upload is "not supported by Slack".
              env =
                {
                  NIXOS_XDG_OPEN_USE_PORTAL = "1";
                  XDG_DATA_DIRS = "${pkgs.shared-mime-info}/share";
                }
                // env;
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
  # when the latter is absent, so dropping the file in is the whole override.
  # Keybinds and rationale live in packages/dwl/config.h.
  # v0.9 ahead of nixpkgs (still 0.8 on wlroots 0.19): 0.9 adds ext-image-
  # capture-source + ext-foreign-toplevel-list, which xdg-desktop-portal-wlr
  # needs to share single windows, including ones on hidden tags.
  dwl = (pkgs.dwl.override {wlroots_0_19 = pkgs.wlroots_0_20;}).overrideAttrs (old: {
    version = "0.9";
    src = pkgs.fetchFromCodeberg {
      owner = "dwl";
      repo = "dwl";
      rev = "v0.9";
      hash = "sha256-PYBOi/A9n1611XBEaZW9PolSfjwe1KWoI2VbVrS2s0Q=";
    };
    patches =
      (old.patches or [])
      ++ [
        ./packages/dwl/patches/movestack-0.8.patch
        # Keybindings are latin; without this none of them fire while the
        # ru group is active (keysyms are looked up in the active layout).
        ./packages/dwl/patches/latin-keybindings.patch
        # Prefix-key modes (Super+R layout, Super+Alt+N notifications). Adds a
        # "<output> mode <label>" status line that dwl-status
        # (profiles/layer-compositor.nix) turns into the bar's mode badge.
        ./packages/dwl/patches/modes-0.9.patch
        # tile() follows the output shape: master|stack on landscape, master
        # over stack on portrait (the work monitors). Also adds bstack as a
        # standalone layout, so layout tracks the kanshi transform.
        ./packages/dwl/patches/autotile-0.8.patch
        # raiseorspawn(): focus the last-focused client with a given app_id
        # (switching to its tags/monitor), else spawn. Single-instance binds
        # in config.h (Super+Alt+T, Super+Alt+M).
        ./packages/dwl/patches/raiseorspawn-0.8.patch
      ];
    postPatch =
      (old.postPatch or "")
      + ''
        cp ${dwlConfig} config.h
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
    camera = true;
  };

  whisper-cpp-vulkan = whisperCppVulkan;

  # autoPatchelfHook rewrites DT_NEEDED only, so CEF's dlopen(libpulse) misses
  # and audio drops to ALSA; without PULSE_PROP the stream says "Chromium".
  grayjay = pkgs.grayjay.overrideAttrs (old: {
    makeWrapperArgs =
      (old.makeWrapperArgs or [])
      ++ [
        "--prefix"
        "LD_LIBRARY_PATH"
        ":"
        (lib.makeLibraryPath [pkgs.libpulseaudio])
        "--set-default"
        "PULSE_PROP"
        "application.name=Grayjay application.icon_name=grayjay"
      ];
  });

  transcribe = pkgs.callPackage ./packages/transcribe.nix {
    whisper-cpp-vulkan = whisperCppVulkan;
  };

  # Separate tool, not a flag on transcribe: Parakeet is a transducer served by
  # sherpa-onnx and its options don't overlap whisper's.
  transcribe-parakeet = pkgs.callPackage ./packages/transcribe-parakeet.nix {};
}
