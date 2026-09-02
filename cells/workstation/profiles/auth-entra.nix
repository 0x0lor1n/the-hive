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

      # Hello PIN enrollment once left an account unable to log in after a
      # mistyped PIN mid-flow; keep disabled until that UX is tested.
      enable_hello = false;

      # Required for Entra login: tenant Conditional Access blocks the
      # PRT->access-token exchange for non-compliant devices, and
      # apply_policy is what lets enrollment/compliance happen at all.
      apply_policy = true;

      # TEMPORARY diagnostic toggle (live-only; resets to false on every
      # switch-to-configuration per iter 9.2.8's own note) — flips RUST_LOG
      # to debug in both himmelblaud and himmelblaud_tasks (cfg.get_debug()
      # in daemon.rs/tasks_daemon.rs) so CustomComplianceCSE's decode/
      # execute/evaluate/submit trail is visible. Investigating why the
      # device stays "Not evaluate" in Intune despite one apply_intune_policy
      # call reaching real policy processing. Revert once understood.
      debug = true;
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

  # The daemon's own state and cache must survive the @blank rollback, or
  # the device re-enrolls with Entra on every boot.
  #
  # Declared HERE rather than in storage-impermanence.nix (iter 11): these
  # entries name `user`/`group` = himmelblaud, which the block just above
  # creates. A host without auth-entra has no such account, so a shared
  # impermanence profile carrying them would break every headless host.
  #
  # Static user (not DynamicUser, see below), plain paths, no
  # /var/lib/private idmap indirection; the TPM seal is bound to the TPM
  # itself so this is safe across a stable uid.
  environment.persistence."/persist".directories = [
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
  ];

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

  # Tenant Intune discovery scripts call gsettings/awk, which aren't in the
  # module's curated PATH for this unit.
  systemd.services.himmelblaud-tasks.path = [
    pkgs.glib # gsettings
    pkgs.gawk # awk
  ];

  # /etc/krb5.conf.d — silences non-fatal Kerberos ccache log spam (no
  # on-prem AD here). /etc/cron.d — himmelblau's ScriptsCSE hard-fails
  # writing recurring policy scripts if this dir is missing. /bin/bash,
  # /usr/bin/bash, /bin/dash — the tenant's Intune custom-compliance
  # discovery scripts exec directly via their shebang, and none of these
  # interpreters exist on NixOS by default.
  systemd.tmpfiles.rules = [
    "d /etc/krb5.conf.d 0755 root root -"
    "d /etc/cron.d 0755 root root -"
    "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
    "L+ /usr/bin/bash - - - - ${pkgs.bash}/bin/bash"
    "L+ /bin/dash - - - - ${pkgs.dash}/bin/dash"
  ];

  # TPM resource-manager access for the static himmelblaud user (no
  # security.tpm2/tss group here). nvme0n1p3 symlink lets the tenant's
  # disk-encryption script (hardcoded to that Ubuntu NVMe path) find our
  # real encrypted partition (vda2) under the name it expects.
  services.udev.extraRules = ''
    KERNEL=="tpmrm0", GROUP="himmelblaud", MODE="0660"
    KERNEL=="vda2", SYMLINK+="nvme0n1p3"
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
