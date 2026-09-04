# Entra ID authentication via himmelblau (NSS + PAM). The local user
# (layer-users-local) stays as the break-glass fallback: pam_himmelblau is
# `sufficient` above pam_unix.
#
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

    # Bumps libhimmelblau 0.8.30 -> 0.8.34 (upstream himmelblau main is
    # still pinned to 0.8.30 as of its latest commit, so this can't be
    # picked up via a plain `nix flake update`). This is a real fix, not a
    # throwaway diagnostic bump: 0.8.34's intune.rs adds
    # http_status_error()/sanitize_http_error_body(), which surfaces the
    # server's actual response body instead of the bare "General failure:
    # 500 Internal Server Error" we've been stuck reading, AND adds
    # IntunePlatformInfo::current()/for_details(), which reads
    # /etc/os-release properly (falling back to /proc/sys/kernel/osrelease)
    # instead of reporting the OSVersion/OSDistribution placeholder that
    # shows up as "0.0.0.0" in the Intune portal.
    #
    # Verified safe as a two-line version+hash swap: fetched both 0.8.30
    # and 0.8.34 from crates.io and diffed Cargo.toml -- identical except
    # the version bump. The new intune.rs code uses the `os-release` and
    # `uuid` crates, but both were already direct dependencies in 0.8.30's
    # Cargo.toml (just unused there), so crate2nix's dependency graph in
    # Cargo.nix needs no new crates, only this version+sha256 swap. Also
    # confirmed both the old version string and old sha256 appear exactly
    # once in Cargo.nix (grep -c), so this can't collide with another crate.
    grep -q 'version = "0.8.30";' $out/Cargo.nix
    grep -q '1v4kwsiplpgws93pp6715w6ncc6dkc2rs0mxjzi3gwyf2855545i' $out/Cargo.nix
    sed -i 's/version = "0.8.30";/version = "0.8.34";/' $out/Cargo.nix
    sed -i 's/1v4kwsiplpgws93pp6715w6ncc6dkc2rs0mxjzi3gwyf2855545i/16km8iwsr1155h1z13k74dl1km3nnbg7r01yx3jj3h05byf9ma6n/' $out/Cargo.nix
    grep -q 'version = "0.8.34";' $out/Cargo.nix

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
in {
  imports = [inputs.himmelblau.nixosModules.himmelblau];

  services.himmelblau = {
    enable = true;
    daemonPackage = lib.mkForce patchedHimmelblau.packages.daemon;

    # swaylock needs pam_himmelblau too (the module only wires the
    # passwd/login/systemd-user defaults); without it Entra users cannot unlock
    # their own session (no /etc/shadow entry for pam_unix to check). greetd is
    # NOT listed: this nixpkgs' greetd PAM service is a
    # substack/include of `login` with useDefaultRules = false, so it inherits
    # himmelblau from there and has no `unix` rule for the module to order on.
    pamServices = [
      "passwd"
      "login"
      "systemd-user"
      "swaylock"
    ];

    # OpenSSH bug 2876 workaround, needed for MFA prompts over SSH.
    mfaSshWorkaroundFlag = true;

    settings = {
      # From the ENCRYPTED half of globals (iter 11.6). The tenant domain
      # identifies the employer, and globals-options.nix flagged it as the
      # clearest candidate for the encrypted half back in iteration 10.
      # Any user in these domains may log in (no group filter yet).
      domain = globals.entra.domains;

      # Every Entra user joins these for compositor + sudo access.
      local_groups = [
        "wheel"
        "video"
        "audio"
        "input"
      ];

      # Software HSM with its AuthCode sealed to the TPM if present — pairs
      # safely with iter 5's LUKS+PCR7 TPM unlock.
      hsm_type = "tpm_bound_soft_if_possible";

      # Readable /home/<upn> plus a /home/<cn> alias (default
      # home_attr is an opaque GUID).
      home_prefix = "/home/";
      home_attr = "spn";
      home_alias = "cn";

      shell = "/run/current-system/sw/bin/bash";
      # Lets the local console accept password-only; MFA still enforced
      # over SSH. Without this, console login can force the device-code flow.
      allow_console_password_only = true;

      # Hello PIN: after the first password+MFA login himmelblau offers to
      # set a PIN, then greetd accepts PIN only. PIN is sealed to the TPM
      # (hsm_type above); the store lives in /var/cache/himmelblaud (persisted).
      enable_hello = true;

      # Required for Entra login: tenant Conditional Access blocks the
      # PRT->access-token exchange for non-compliant devices, and
      # apply_policy is what lets enrollment/compliance happen at all.
      apply_policy = true;

    };
  };

  # himmelblau's workspace builds against WebKitGTK (aad-tool / Hello-PIN
  # enrollment flows), which renders blank white on this VM's virtio-GPU
  # without this — the same DMA-BUF bug the retired intune-portal/broker
  # stack hit. sessionVariables covers anything launched interactively
  # (aad-tool, a terminal); the unit override covers himmelblau-broker
  # itself, since — unlike the real microsoft-identity-broker — it's a
  # genuine systemd --user service and doesn't need the
  # dbus-update-activation-environment dance to see the variable.
  environment.sessionVariables.WEBKIT_DISABLE_DMABUF_RENDERER = "1";
  systemd.user.services.himmelblau-broker.environment.WEBKIT_DISABLE_DMABUF_RENDERER = "1";

  # himmelblaud (main) must run as a static non-root user: DynamicUser's
  # /var/lib/private state dir collides with impermanence's bind mount, and
  # it doesn't need root — it delegates privileged work to himmelblaud-tasks.
  users.users.himmelblaud = {
    isSystemUser = true;
    group = "himmelblaud";
    description = "Himmelblau authentication daemon";
  };
  users.groups.himmelblaud = {};

  # nsncd runs libnss_himmelblau.so as the nscd user, not himmelblaud —
  # needs group read on the daemon's cache files or every NSS lookup EACCESs.
  users.users.nscd.extraGroups = ["himmelblaud"];

  # Daemon state/cache: without it the device re-enrolls every boot. Lives
  # here, not in storage-impermanence, because it names the himmelblaud
  # user created above.
  #
  # Entra user's home: Edge profile (corp login) + bash history. NSS-only
  # account, so `persistence.users.<name>` (needs users.users) is out --
  # absolute paths + numeric uid from the encrypted globals. impermanence
  # creates the *parents* of a bind mount with defaultPerms (root 0755), so
  # the tmpfiles rules below re-own the home and its xdg dirs.
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
      (entraHome ".cache/microsoft-edge")
      # Slack (HM home.packages of the Entra user, layer-compositor.nix):
      # session token + workspace list live here; cache is disposable.
      (entraHome ".config/Slack")
      (entraHome ".local/share/bash")
    ];

  # HISTFILE into the persisted dir instead of persisting ~/.bash_history
  # as a file (avoids the persist-files symlink race on first shell).
  programs.bash.interactiveShellInit = ''
    [ -d "$HOME/.local/share/bash" ] && export HISTFILE="$HOME/.local/share/bash/history"
  '';

  systemd.services.himmelblaud.serviceConfig.ExecStartPost = [
    "+${pkgs.writeShellScript "himmelblaud-fix-perms" ''
      set -u
      # ExecStartPost fires as soon as the main process is spawned, but the
      # daemon writes himmelblau.conf / himmelblau.cache.db slightly later
      # during its own init. On a fresh pool neither exists yet, so chmod
      # used to ENOENT and take the whole unit down with it (it then came
      # back on the automatic restart, once the files were there). Wait for
      # them instead. Modes are load-bearing: nscd needs group read on the
      # cache db or every NSS lookup EACCESes, and 0750 on the directory is
      # what silences the daemon's "'everyone' permission bits" warning.
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

  # First login after boot used to prompt `Password:` instead of the Hello
  # PIN: greetd came up before himmelblaud had opened its socket, so
  # pam_himmelblau returned PAM_IGNORE and the stack fell through to pam_unix
  # ("check pass; user unknown" for Entra users). The retry a few seconds
  # later hit a live daemon and got the PIN. Order greetd after the daemon.
  systemd.services.greetd = {
    wants = ["himmelblaud.service"];
    after = ["himmelblaud.service"];
  };

  systemd.services.himmelblaud.serviceConfig = {
    # Plain non-idmap state dir (impermanence-friendly); no extra caps needed.
    DynamicUser = lib.mkForce false;
    User = "himmelblaud";
    Group = "himmelblaud";
  };

  systemd.services.himmelblaud-tasks.serviceConfig = {
    # Must be real root (main daemon only accepts uid==0 peers) and able to
    # setuid/chown into the logging-in user; module's NoNewPrivileges blocked that.
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

    # Module sets PrivateDevices=true, hiding real block devices from any
    # discovery script this daemon runs — needed for disk-encryption checks.
    PrivateDevices = lib.mkForce false;
  };

  # Tenant Intune discovery scripts call gsettings/awk/zfs/zpool, which
  # aren't in the module's curated PATH for this unit (shadow, bash,
  # util-linux). The disk-encryption compliance script in particular
  # falls through to `command -v zfs || return 1` and reports "false"
  # for a fully encrypted native-ZFS root when zfs is missing here.
  systemd.services.himmelblaud-tasks.path = [
    pkgs.glib # gsettings
    pkgs.gawk # awk
    config.boot.zfs.package # zfs, zpool
  ];

  # /etc/krb5.conf.d — silences non-fatal Kerberos ccache log spam (no
  # on-prem AD here). /etc/cron.d — himmelblau's ScriptsCSE hard-fails
  # writing recurring policy scripts if this dir is missing. /bin/bash,
  # /usr/bin/bash, /bin/dash — the tenant's Intune custom-compliance
  # discovery scripts exec directly via their shebang, and none of these
  # interpreters exist on NixOS by default.
  systemd.tmpfiles.rules = let
    inherit (globals.entra.user) upn uid;
    own = sub: "d /home/${upn}${sub} 0700 ${toString uid} ${toString uid} -";
  in
    [
      "d /etc/krb5.conf.d 0755 root root -"
      "d /etc/cron.d 0755 root root -"
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
      "L+ /usr/bin/bash - - - - ${pkgs.bash}/bin/bash"
      "L+ /bin/dash - - - - ${pkgs.dash}/bin/dash"
    ]
    # /home/<upn> itself is 0750: himmelblau creates it that way (umask 027)
    # and the /home/<cn> alias must stay traversable. .local/state is where
    # home-manager-entra registers its generation.
    ++ lib.optionals (upn != null && uid != null) [
      "d /home/${upn} 0750 ${toString uid} ${toString uid} -"
      (own "/.config")
      (own "/.cache")
      (own "/.local")
      (own "/.local/share")
      (own "/.local/state")
      (own "/.local/state/nix")
      (own "/.local/state/nix/profiles")
    ];

  # TPM resource-manager access for the static himmelblaud user (no
  # security.tpm2/tss group here).
  #
  # There used to be a `vda2 -> nvme0n1p3` symlink here for the tenant's
  # disk-encryption compliance script. Gone: that script (user-authored) finds
  # the root via `findmnt -no SOURCE /` and checks `zfs get encryptionroot/
  # encryption/keystatus`; its `/dev/nvme0n1p3` probe is the Ubuntu/LUKS
  # legacy branch and is meant to fall through on ZFS hosts. All it needs
  # from us is zfs/zpool/findmnt on the unit's PATH (below).
  services.udev.extraRules = ''
    KERNEL=="tpmrm0", GROUP="himmelblaud", MODE="0660"
  '';

  # The tenant's screen-idle-lock script reads GNOME's dconf idle-delay
  # specifically; this session really does lock at 300s (see idle.nix),
  # just not through a schema this script knows to look for.
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/session" = {
        idle-delay = lib.gvariant.mkUint32 300;
      };
    }
  ];
  # gsettings can't find the schema without this — no GNOME session here to
  # wire up XDG_DATA_DIRS automatically, and environment.variables doesn't
  # reach himmelblaud-tasks (it has its own explicit unit environment).
  environment.variables.GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
  systemd.services.himmelblaud-tasks.environment.GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";

  # First enrollment needs two MFA rounds (password + Hello-PIN setup),
  # which blows past login(1)'s default 60s timeout on the serial console.
  security.loginDefs.settings.LOGIN_TIMEOUT = 300;

  # aad-tool from patchedHimmelblau (not the flake's own build) so its
  # "tpm" feature — and therefore `aad-tool tpm` — actually works.
  environment.systemPackages = [
    patchedHimmelblau.packages.aad-tool
    pkgs.glib
    pkgs.gsettings-desktop-schemas
  ];
}
