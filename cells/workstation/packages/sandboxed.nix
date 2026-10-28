# Desktop apps behind bwrap + xdg-dbus-proxy (nixpak), built per account:
# layer-compositor.nix calls this from mkAccount, packages.nix with the
# defaults for `nix build`.
#
# canonicalHome: an Entra account's $HOME is the /home/<cn> alias himmelblau
# creates (auth-entra.nix); the real directory is /home/<upn>. Anything that
# canonicalises before handing a path over (GIO: Thunar's cwd, hence
# drag-and-drop URIs) names /home/<upn>, which doesn't exist in the sandbox:
# bwrap mounts $HOME/... as a plain directory tree, the alias is no symlink
# inside, so the shared dirs are bound at that name too. null for an account
# whose $HOME is the real path (local).
{
  inputs,
  pkgs,
  lib,
  canonicalHome ? null,
}: let
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
              lib.optional (canonicalHome != null)
              [(sloth.mkdir (sloth.concat' sloth.homeDir sub)) "${canonicalHome}${sub}"];
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
                  # Same dir under canonicalHome (see the header). Assumes the
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
}
