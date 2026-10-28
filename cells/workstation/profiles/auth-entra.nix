# Entra ID login via himmelblau (NSS + PAM); the local account stays as break-glass,
# pam_himmelblau is `sufficient` above pam_unix.
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
  patchedHimmelblauSrc = pkgs.runCommand "himmelblau-patched-src" {} ''
    cp -r ${inputs.himmelblau} $out
    chmod -R u+w $out
    # Retries CustomComplianceCSE's script spawn on ENOENT — mitigates a
    # benign TOCTOU race where exec on a just-written temp file intermittently fails.
    patch -p1 -d $out < ${./patches/himmelblau/0001-custom-compliance-retry-enoent.patch}

    # Bumps libhimmelblau 0.8.30 -> 0.8.39; the pinned himmelblau commit wants
    # 0.8.30, upstream main's 0.8.37 is a bigger jump than this needs.
    # 0.8.39 (2026-09-04) is the fix: Intune check-in started answering
    # LinuxDeviceCheckinService/status in camelCase, 0.8.30 only knew
    # PascalCase, so every ApplyPolicy died on `Invalid JSON: missing field
    # PolicyId` and the device went non-compliant.
    # Safe as a version+hash swap: those Cargo.toml versions differ only in
    # the version line, so Cargo.nix needs no new crates, and both old strings
    # appear exactly once. Hash = `nix hash file --type sha256 --base32`.
    grep -q 'version = "0.8.30";' $out/Cargo.nix
    grep -q '1v4kwsiplpgws93pp6715w6ncc6dkc2rs0mxjzi3gwyf2855545i' $out/Cargo.nix
    sed -i 's/version = "0.8.30";/version = "0.8.39";/' $out/Cargo.nix
    sed -i 's/1v4kwsiplpgws93pp6715w6ncc6dkc2rs0mxjzi3gwyf2855545i/16lwc932ywpklmjsrwypkdjnq3sqxpqxmmy5jsrym5ks7qilqhv3/' $out/Cargo.nix
    grep -q 'version = "0.8.39";' $out/Cargo.nix

    # Enables himmelblau's "tpm" feature (real TPM 2.0 support) for the
    # daemon + aad-tool; upstream default.nix never wires up the native
    # tpm2-tss dependency tss-esapi-sys needs to build with it.
    substituteInPlace $out/default.nix \
      --replace-fail \
        'himmelblau_unix_common = attrs: {' \
        '"tss-esapi-sys" = attrs: {
            nativeBuildInputs = [
              pkgs.pkg-config
            ];
            buildInputs = [
              pkgs.tpm2-tss
            ];
            LIBCLANG_PATH = "''${pkgs.llvmPackages.libclang.lib}/lib";
            BINDGEN_EXTRA_CLANG_ARGS = pkgs.lib.concatStringsSep " " [
              "-isystem ''${pkgs.llvmPackages.libclang.lib}/lib/clang/''${pkgs.llvmPackages.libclang.version}/include"
              "-isystem ''${pkgs.glibc.dev}/include"
            ];
          };
          # tss-esapi build.rs reads DEP_TSS2_ESYS_VERSION (its real Cargo
          # `links` name); buildRustCrate guesses the wrong DEP_* prefix
          # from the -sys crate package name instead, so set it directly.
          "tss-esapi" = attrs: {
            DEP_TSS2_ESYS_VERSION = pkgs.tpm2-tss.version;
          };
          himmelblau_unix_common = attrs: {' \
      --replace-fail \
        'daemon = cargo_nix.workspaceMembers."himmelblaud".build;' \
        'daemon = cargo_nix.workspaceMembers."himmelblaud".build.override {
      features = [ "default" "himmelblau_unix_common/tpm" ];
    };' \
      --replace-fail \
        'aad-tool = cargo_nix.workspaceMembers."aad-tool".build;' \
        'aad-tool = cargo_nix.workspaceMembers."aad-tool".build.override {
      features = [ "default" "himmelblau_unix_common/tpm" ];
    };'
  '';
  patchedHimmelblau = import "${patchedHimmelblauSrc}/default.nix" {inherit pkgs;};

  # As the https handler, o365-url-handler's own `exec xdg-open` fallbacks would loop back into it.
  xdgOpenShim = pkgs.writeShellScriptBin "xdg-open" ''
    exec firefox "$@"
  '';
  # Patched after build (postInstall rewrites its /usr paths); bare SharePoint links carry no ?file=.
  # Allowlist untouched: o365-multi has require() in page scope, a wrong entry is code execution.
  o365UrlHandlerBin = pkgs.runCommand "o365-url-handler" {nativeBuildInputs = [pkgs.makeWrapper];} ''
    mkdir -p $out/bin $out/libexec
    cp ${patchedHimmelblau.packages.o365}/bin/o365-url-handler $out/libexec/
    chmod +w $out/libexec/o365-url-handler

    substituteInPlace $out/libexec/o365-url-handler \
      --replace-fail \
        '  # Unknown/extension-less (e.g., many OneNote links) -> let the browser handle it' \
        '  case "$HOST" in
        *.sharepoint.com|*.sharepoint.us|*.sharepoint-mil.us|*.sharepoint.cn|*.sharepoint.de)
          exec "$O365_LAUNCHER" --url="$URL" --profile=SharePoint \
            --appIcon=${patchedHimmelblau.packages.o365}/share/icons/hicolor/256x256/apps/o365-sharepoint.png \
            --appTitle=SharePoint --closeAppOnCross=true --trayIconEnabled=false ;;
      esac'

    makeWrapper $out/libexec/o365-url-handler $out/bin/o365-url-handler \
      --prefix PATH : ${lib.makeBinPath [xdgOpenShim pkgs.gawk]}
  '';

  o365UrlHandler = pkgs.symlinkJoin {
    name = "o365-url-handler-with-desktop";
    paths = [
      o365UrlHandlerBin
      (pkgs.makeDesktopItem {
        name = "o365-url-handler";
        desktopName = "Microsoft 365 link handler";
        comment = "Open Microsoft 365 documents in their app, everything else in Firefox";
        exec = "${o365UrlHandlerBin}/bin/o365-url-handler %U";
        noDisplay = true;
        mimeTypes = ["x-scheme-handler/https"];
      })
    ];
  };

  hasEntra = lib.any (a: a.auth == "entra") config.hive.accounts;

  # himmelblau's login-time gpasswd is lost at each switch and lands after user@.service resolved
  # its groups. cn, not upn: cn_name_mapping=true makes NSS return the cn as the login.
  entraLocalGroups = lib.optionalAttrs (globals.entra.user.upn != null) (
    lib.genAttrs config.services.himmelblau.settings.local_groups (_: {
      members = [(lib.head (lib.splitString "@" globals.entra.user.upn))];
    })
  );
in {
  imports = [inputs.himmelblau.nixosModules.himmelblau];

  # A host without an Entra account (penrose) gets only the module's options.
  config = lib.mkIf hasEntra {
    services.himmelblau = {
      enable = true;
      daemonPackage = lib.mkForce patchedHimmelblau.packages.daemon;

      # swaylock: Entra users have no shadow entry for pam_unix. greetd is a substack of
      # `login` (useDefaultRules = false), inherits himmelblau there and has no unix rule.
      pamServices = [
        "passwd"
        "login"
        "systemd-user"
        "swaylock"
      ];

      # OpenSSH bug 2876 workaround, needed for MFA prompts over SSH.
      mfaSshWorkaroundFlag = true;

      settings = {
        # Encrypted: the domain names the employer. No group filter, any tenant user may log in.
        domain = globals.entra.domains;

        # No wheel: sudo, polkit admin and nix trusted-users stay with the local account.
        local_groups = [
          # /dev/tpmrm0: PIN-less age-plugin-tpm identities for work-repo secrets.
          # Host agenix identities keep their PIN.
          "himmelblaud"
          "video"
          "audio"
          # No "input": /dev/input/event* would let this account keylog every session on the
          # seat. dwl takes devices via logind, Vial via its hidraw uaccess rule.
          # rw /srv/the-hive (srv-the-hive.nix)
          "hive"
          # NetworkManager's polkit policy and vpn.nix's manage-units rule key on this group.
          "networkmanager"
          # himmelblau uids fall in journald's container range: no user-<uid>.journal to read.
          "systemd-journal"
        ];

        hsm_type = "tpm_bound_soft_if_possible";

        # /home/<upn> plus a /home/<cn> alias; the default home_attr is a GUID.
        home_prefix = "/home/";
        home_attr = "spn";
        home_alias = "cn";

        # Present via programs.zsh.enable (layer-users-local.nix).
        shell = "/run/current-system/sw/bin/zsh";
        # Without it console login can force the device-code flow; SSH still enforces MFA.
        allow_console_password_only = true;

        # After the first password+MFA login greetd accepts the TPM-sealed PIN only.
        enable_hello = true;

        # Conditional Access blocks the PRT->token exchange on non-compliant devices.
        apply_policy = true;

        # TEMP: greetd restarts the PAM conversation after a successful PIN auth_step
        # (second auth_init falls back to password+MFA). Remove once diagnosed.
        debug = true;
      };
    };

    # WebKitGTK (aad-tool, Hello enrollment) renders blank on virtio-GPU with DMA-BUF.
    # himmelblau-broker is a systemd --user unit and does not see sessionVariables.
    environment.sessionVariables.WEBKIT_DISABLE_DMABUF_RENDERER = "1";
    systemd.user.services.himmelblau-broker.environment.WEBKIT_DISABLE_DMABUF_RENDERER = "1";

    # Static user: DynamicUser's /var/lib/private collides with the impermanence bind mount.
    users.users.himmelblaud = {
      isSystemUser = true;
      group = "himmelblaud";
      description = "Himmelblau authentication daemon";
    };
    users.groups = {himmelblaud = {};} // entraLocalGroups;

    # nsncd loads libnss_himmelblau as nscd and needs group read on the daemon's cache.
    users.users.nscd.extraGroups = ["himmelblaud"];

    # Without daemon state the device re-enrolls every boot. The Entra account is NSS-only, so no
    # persistence.users: absolute paths and numeric uid; tmpfiles below re-owns the parents.
    environment.persistence."/persist".directories = let
      inherit (globals.entra.user) upn uid;
      entraHome = sub: {
        directory = "/home/${upn}/${sub}";
        user = toString uid;
        group = toString uid;
        mode = "0700";
      };
    in
      [
        {
          directory = "/var/lib/himmelblaud";
          user = "himmelblaud";
          group = "himmelblaud";
          mode = "0700";
        }
        {
          directory = "/var/cache/himmelblaud";
          user = "himmelblaud";
          group = "himmelblaud";
          mode = "0700";
        }
      ]
      ++ lib.optionals (upn != null && uid != null) [
        (entraHome ".config/microsoft-edge")
        # Firefox 154+ keeps the profile here, not in ~/.mozilla.
        (entraHome ".config/mozilla")
        (entraHome ".config/teams-for-linux")
        (entraHome ".config/o365-profiles")
        # nixpak apps: config/data/cache under one Flatpak-style dir each.
        (entraHome ".var/app/com.slack.Slack")
        (entraHome ".var/app/org.telegram.desktop")
        # Horizon: server list, prefs, plus the gm sign-in Chromium profile.
        (entraHome ".omnissa")
        (entraHome ".hermes")
        (entraHome ".claude")
        (entraHome ".local/share/bash")
        # Mirrors layer-users-local.nix. .ssh for known_hosts: keys are age.secrets, config an HM link.
        (entraHome ".ssh")
        (entraHome ".local/share/direnv")
        (entraHome ".local/share/zsh")
        (entraHome ".local/share/zoxide")
        (entraHome ".local/share/tmux/resurrect")
        (entraHome ".local/state/lazygit")
        (entraHome ".local/share/nvim")
        (entraHome ".local/share/asr-models")
        # Whole ~/.cache: impermanence does not dedup nested bind mounts, so no .cache/* entries.
        (entraHome ".cache")
        (entraHome ".config/opencode")
        (entraHome ".local/share/opencode")
        (entraHome ".config/Mattermost")
        (entraHome ".local/share/simplex")
        (entraHome ".local/share/mpd")
        (entraHome ".config/keepassxc")
        (entraHome ".local/share/keepassxc")
        (entraHome ".config/qBittorrent")
        (entraHome ".local/share/qBittorrent")
        (entraHome ".local/share/Grayjay")
        (entraHome ".config/herdr")
        (entraHome ".local/state/herdr")
      ];

    # A persisted ~/.bash_history file races the persist-files symlink on first shell.
    programs.bash.interactiveShellInit = ''
      [ -d "$HOME/.local/share/bash" ] && export HISTFILE="$HOME/.local/share/bash/history"
    '';

    # Each switch rewrites /etc/sub{u,g}id, dropping himmelblau's login-time entry (it skips existing
    # names). 2100000000 = start of its subid_range, clear of idmap_range and the NixOS auto range.
    system.activationScripts.entra-subids = lib.mkIf (globals.entra.user.upn != null) (
      lib.stringAfter ["users"] (let
        cn = lib.head (lib.splitString "@" globals.entra.user.upn);
        entry = "${cn}:2100000000:65536";
      in ''
        for f in /etc/subuid /etc/subgid; do
          grep -qs '^${cn}:' "$f" || echo '${entry}' >> "$f"
        done
      '')
    );

    systemd.services.himmelblaud.serviceConfig.ExecStartPost = [
      "+${pkgs.writeShellScript "himmelblaud-fix-perms" ''
        set -u
        # The daemon writes these after ExecStartPost fires; on a fresh pool chmod would fail the unit.
        # nscd needs group read on the cache db; 0750 silences the "'everyone' permission bits" warning.
        ${pkgs.coreutils}/bin/chmod 750 /var/cache/himmelblaud || true

        for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
          if [ -e /var/cache/himmelblaud/himmelblau.conf ] \
          && [ -e /var/cache/himmelblaud/himmelblau.cache.db ]; then
            break
          fi
          ${pkgs.coreutils}/bin/sleep 0.1
        done

        [ -e /var/cache/himmelblaud/himmelblau.conf ] \
          && ${pkgs.coreutils}/bin/chmod 644 /var/cache/himmelblaud/himmelblau.conf
        [ -e /var/cache/himmelblaud/himmelblau.cache.db ] \
          && ${pkgs.coreutils}/bin/chmod 640 /var/cache/himmelblaud/himmelblau.cache.db
        exit 0
      ''}"
    ];

    # Without the daemon's socket pam_himmelblau returns PAM_IGNORE and greetd asks for a password.
    systemd.services.greetd = {
      wants = ["himmelblaud.service"];
      after = ["himmelblaud.service"];
    };

    systemd.services.himmelblaud.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "himmelblaud";
      Group = "himmelblaud";
    };

    systemd.services.himmelblaud-tasks.serviceConfig = {
      # Real root: the daemon accepts only uid 0 peers, and tasks setuid/chown into the user.
      User = lib.mkForce "root";
      Group = lib.mkForce "root";
      NoNewPrivileges = lib.mkForce false;
      AmbientCapabilities = [
        "CAP_SETUID"
        "CAP_SETGID"
        "CAP_CHOWN"
        "CAP_DAC_OVERRIDE"
        "CAP_FOWNER"
      ];
      CapabilityBoundingSet = [
        "CAP_SETUID"
        "CAP_SETGID"
        "CAP_CHOWN"
        "CAP_DAC_OVERRIDE"
        "CAP_FOWNER"
        "CAP_DAC_READ_SEARCH"
      ];

      # Disk-encryption compliance scripts need the real block devices.
      PrivateDevices = lib.mkForce false;
    };

    # Tenant Intune discovery scripts; without zfs the encryption check reports false on a ZFS root.
    systemd.services.himmelblaud-tasks.path = [
      pkgs.glib # gsettings
      pkgs.gawk # awk
      config.boot.zfs.package # zfs, zpool
    ];

    # krb5.conf.d silences ccache log spam; ScriptsCSE fails without cron.d; the tenant's
    # compliance scripts exec bash/dash by shebang path.
    systemd.tmpfiles.rules = let
      inherit (globals.entra.user) upn uid;
      cn = lib.head (lib.splitString "@" upn);
      # Activation copies owner/mode from /persist onto the live home, and impermanence creates
      # undeclared parents there as root 0755, so both sides are owned here.
      own = sub: "d /home/${upn}${sub} 0700 ${toString uid} ${toString uid} -";
      ownBoth = sub: [
        (own sub)
        "d /persist/home/${upn}${sub} 0700 ${toString uid} ${toString uid} -"
      ];
    in
      [
        "d /etc/krb5.conf.d 0755 root root -"
        "d /etc/cron.d 0755 root root -"
        "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
        "L+ /usr/bin/bash - - - - ${pkgs.bash}/bin/bash"
        "L+ /bin/dash - - - - ${pkgs.dash}/bin/dash"
      ]
      # 0750 keeps the /home/<cn> alias traversable. himmelblaud_tasks creates the alias only
      # after the first PAM session, which left dwl-session without $HOME on first login.
      ++ lib.optionals (upn != null && uid != null) (
        [
          "d /home/${upn} 0750 ${toString uid} ${toString uid} -"
          "d /persist/home/${upn} 0750 ${toString uid} ${toString uid} -"
          "L /home/${cn} - - - - ${upn}"
        ]
        ++ lib.concatMap ownBoth [
          "/.config"
          "/.cache"
          "/.local"
          "/.local/share"
          "/.local/share/tmux"
          "/.local/state"
          "/.var"
          "/.var/app"
        ]
        # nix/profiles is home-manager-entra's generation, never persisted.
        ++ map own [
          "/.local/state/nix"
          "/.local/state/nix/profiles"
        ]
      );

    # No security.tpm2 tss group here; himmelblaud is a static user.
    services.udev.extraRules = ''
      KERNEL=="tpmrm0", GROUP="himmelblaud", MODE="0660"
    '';

    # The tenant's idle-lock check reads GNOME's idle-delay; the real 300 s lock is idle.nix.
    programs.dconf.profiles.user.databases = [
      {
        settings."org/gnome/desktop/session" = {
          idle-delay = lib.gvariant.mkUint32 300;
        };
      }
    ];
    # No GNOME session sets XDG_DATA_DIRS, and himmelblaud-tasks has its own unit environment.
    environment.variables.GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
    systemd.services.himmelblaud-tasks.environment.GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";

    # First enrollment (two MFA rounds) outlasts login(1)'s 60 s default on the serial console.
    security.loginDefs.settings.LOGIN_TIMEOUT = 300;

    # teams-for-linux 2.17 dropped --ssoInTuneEnabled, still passed by o365.sh:256 (no PRT, Intune
    # wall); drop once it learns auth.intune. Flat followSystemTheme: 2.17.1 ignores appearance.*.
    environment.etc = lib.mkIf (globals.entra.user.upn != null) {
      "teams-for-linux/config.json".text = builtins.toJSON {
        auth.intune = {
          enabled = true;
          user = globals.entra.user.upn;
        };
        followSystemTheme = true;
      };
    };

    environment.systemPackages = [
      # The flake's own aad-tool lacks the tpm feature.
      patchedHimmelblau.packages.aad-tool
      patchedHimmelblau.packages.o365
      # https default (layer-compositor.nix); its .desktop must be on XDG_DATA_DIRS for every account.
      o365UrlHandler
      pkgs.glib
      pkgs.gsettings-desktop-schemas
    ];
  };
}
