# ZFS TPM2 unlock with anti-confusion and anti-replay protection
#
# Anti-confusion: PCR 15 extended with ZFS fingerprints BEFORE unseal.
#   Fake volumes -> wrong fingerprint -> PCR mismatch -> unseal fails.
# Anti-replay: PCR 15 extended with zeros AFTER unseal.
#   Credential cannot be unsealed again until next reboot.
#
# Measured, and worth knowing before changing any of this: `zfs change-key`
# leaves DSL_CRYPTO_GUID alone but recomputes DSL_CRYPTO_MAC, so the
# fingerprint moves on every rewrap. That makes the fingerprint a wrapping-key
# generation counter as well as a pool identity -- restoring an older wrapped
# key yields a different PCR 15 and refuses to unseal. Do not "simplify"
# __zfs-fingerprint.nix to hash the GUID alone; it would look equivalent and
# silently drop that property.
#
# Why the credential lives on the ESP and not in the initrd
# --------------------------------------------------------
# It used to be a flake-source path fed to boot.initrd.secrets. That works, but
# only because a content change there also changes the toplevel, hence the
# generation, hence the UKI -- so the rebuild was guaranteed by accident.
# Lanzaboote's install_generation() returns early when
# register_installed_generation() succeeds, and that check only confirms the
# stub and its .linux/.initrd targets exist; it never compares content. So a
# re-seal that does not change the generation would leave the old credential
# baked into the signed UKI, and rotation would silently not take effect.
#
# Reading it from the ESP at runtime makes re-sealing a plain file write: no
# UKI rebuild, no deleting signed boot artifacts from a service, and no
# eval-time builtins.readFile (which is what forced the credential to be a
# store path in the first place, and what made the ZFS toplevel hash churn on
# every repo edit). The credential's integrity is not security-critical: it is
# TPM-sealed ciphertext, useless on another machine, and tampering degrades to
# the passphrase prompt.
#
# Why the ESP is mounted INSIDE the unlock script, not by a systemd mount unit
# ---------------------------------------------------------------------------
# It was a boot.initrd.systemd.mounts entry (efi.mount) and it never once
# mounted successfully. Chasing it cost three wrong fixes, each of which was
# verified dead by extracting the initrd rather than by reasoning:
#
#   - wrong device path      real, fixed; disko labels the partition
#                            disk-main-ESP, not ESP
#   - vfat missing           false; vfat.ko.xz was in the initrd all along
#   - vfat loaded too late   false; the ordering chain systemd-modules-load ->
#                            zfs-import-rpool -> zfs-import.target -> efi.mount
#                            is real, and modules-load.d lists vfat
#   - nofail device race     false; the journal says "Found device"
#
# What remained was `mount` exiting 32 one second after the device appeared,
# with the mountpoint /efi absent from the initrd (as it is for EVERY initrd
# mount unit, so that alone proves nothing).
#
# Rather than keep bisecting a mount unit, drop it. The requirement is tiny --
# read one file, once, before the unseal -- and a mount unit is a poor fit for
# it: it needs a mountpoint that already exists, it needs an ordering graph
# with a DefaultDependencies=false hole hand-patched into it, and when it fails
# it prints [FAILED] on every bootstrap boot where the credential legitimately
# does not exist yet. Doing mkdir + mount + read + umount in the script deletes
# all three problems at once, and the "no credential yet" path stops looking
# like a fault. The mount is also open for the few milliseconds it is needed
# instead of from zfs-import until switch-root.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.zfsUnlock;
  zfs = config.boot.zfs.package;

  zfsFingerprint = import ./__zfs-fingerprint.nix {
    inherit pkgs;
    zfsPackage = zfs;
  };

  # Device info: sorted list with derived values computed once.
  #
  # Nothing here reads the credential at eval time, and that is deliberate --
  # see the ESP note in the header. pcrBank used to be sniffed out of the
  # credential's base64 with builtins.readFile; it is now declared.
  devices = map (name: rec {
    inherit name;
    safeName = lib.replaceStrings ["/"] ["_"] name;
    pcrBank = cfg.devices.${name}.pcrBank;
    credPath = "${cfg.espMountPoint}/${cfg.credentialSubdir}/${safeName}.cred";
  }) (lib.sort (a: b: a < b) (lib.attrNames cfg.devices));

  usedBanks = lib.unique (map (d: d.pcrBank) devices);

  pcrZerosForBank = bank:
    lib.concatStrings (
      lib.replicate
      {
        sha1 = 40;
        sha256 = 64;
        sha384 = 96;
        sha512 = 128;
      }
        .${
        bank
      }
      "0"
    );

  tpm2_pcrextend = "${pkgs.tpm2-tools}/bin/tpm2_pcrextend";
  systemd-creds = "${pkgs.systemd}/bin/systemd-creds";
  systemd-ask-password = "${pkgs.systemd}/bin/systemd-ask-password";
  mount = "${pkgs.util-linux}/bin/mount";
  umount = "${pkgs.util-linux}/bin/umount";
  mkdir = "${pkgs.coreutils}/bin/mkdir";

  # The ESP is mounted for exactly as long as it takes to read the credentials,
  # by this script rather than by a systemd mount unit -- see the header for why
  # that unit was removed. Both halves are deliberately non-fatal: a missing or
  # unmountable ESP means "no credential", which is the documented bootstrap
  # state and falls through to the passphrase prompt.
  mountEsp = ''
    esp_mounted=0
    if ${mkdir} -p ${cfg.espMountPoint}; then
      if ${mount} -t vfat -o ro,umask=0077 ${cfg.espDevice} ${cfg.espMountPoint}; then
        esp_mounted=1
      else
        echo "zfs-unlock: could not mount ${cfg.espDevice} at ${cfg.espMountPoint};" \
             "treating credentials as absent (will prompt)"
      fi
    else
      echo "zfs-unlock: could not create ${cfg.espMountPoint}; will prompt"
    fi
  '';

  # Unmount as soon as the credentials are read, so the ESP is free well before
  # switch-root hands it to stage 2 for /boot. A function, not an inline block:
  # it is called both on the happy path and from the EXIT trap, and the flag
  # makes the second call a no-op rather than an error.
  umountEspFn = ''
    unmount_esp() {
      if [[ "$esp_mounted" -eq 1 ]]; then
        ${umount} ${cfg.espMountPoint} || echo "zfs-unlock: WARNING: could not unmount ${cfg.espMountPoint}"
        esp_mounted=0
      fi
    }
  '';

  # No longer gated on an eval-time "does any device have a credential" flag:
  # presence is now a RUNTIME test, because the credential lives on the ESP and
  # may appear or change without a rebuild. `devices` is non-empty (the config
  # guard below ensures it), so the `then` branch is never empty and
  # writeShellScript's shellDryRun checkPhase stays happy.
  tpmUnlockSection = ''
    if [[ "$pcr_ok" -eq 1 ]]; then
      ${lib.concatMapStrings (d: ''
        if [[ "$(${zfs}/bin/zfs get -Ho value keystatus "${d.name}" 2>/dev/null)" == "unavailable" ]]; then
          if [[ -f "${d.credPath}" ]]; then
            echo "zfs-unlock: TPM unlock for ${d.name}..."
            if ${systemd-creds} decrypt --name="${d.name}" "${d.credPath}" - 2>/dev/null \
                | ${zfs}/bin/zfs load-key "${d.name}"; then
              echo "zfs-unlock: Unlocked ${d.name}"
            else
              echo "zfs-unlock: TPM unlock failed for ${d.name}, will prompt for password"
            fi
          else
            echo "zfs-unlock: No credential at ${d.credPath} (bootstrap state), will prompt"
          fi
        fi
      '')
      devices}
    else
      echo "zfs-unlock: Skipping TPM unlock due to PCR errors"
    fi'';

  unlockScript = pkgs.writeShellScript "zfs-tpm-unlock" ''
    set -uo pipefail

    # Declared before the trap is armed so the handler can never see it unset
    # (this script runs under `set -u`). The trap is the safety net for the
    # `exit 1` on a failed unlock; the happy path unmounts explicitly, earlier.
    esp_mounted=0
    ${umountEspFn}
    trap unmount_esp EXIT

    pcr_ok=1
    echo "zfs-unlock: Extending PCR 15 with device fingerprints..."
    ${lib.concatMapStrings (d: ''
        echo "zfs-unlock: Computing fingerprint for ${d.name} (bank: ${d.pcrBank})..."
        if fingerprint=$(${zfsFingerprint.script} "${d.name}" ${d.pcrBank} 2>/dev/null); then
          echo "zfs-unlock: PCR extend for ${d.name} (fingerprint: $fingerprint)"
          if ! ${tpm2_pcrextend} "15:${d.pcrBank}=$fingerprint" 2>&1; then
            echo "zfs-unlock: WARNING: PCR extend failed for ${d.name}"
            pcr_ok=0
          fi
        else
          echo "zfs-unlock: WARNING: Fingerprint computation failed for ${d.name}"
          pcr_ok=0
        fi
      '')
      devices}

    # TPM unlock. The ESP is mounted only across this section -- it is the only
    # part that touches the credential files.
    ${mountEsp}
    ${tpmUnlockSection}
    unmount_esp

    # Password fallback
    ${lib.concatMapStrings (d: ''
        if [[ "$(${zfs}/bin/zfs get -Ho value keystatus "${d.name}" 2>/dev/null)" == "unavailable" ]]; then
          kl=$(${zfs}/bin/zfs get -Ho value keylocation "${d.name}" 2>/dev/null)
          if [[ "$kl" == "prompt" ]]; then
            echo "zfs-unlock: Password prompt for ${d.name}"
            for attempt in 1 2 3; do
              if ${systemd-ask-password} --timeout=${toString config.boot.zfs.passwordTimeout} "Enter key for ${d.name}:" \
                  | ${zfs}/bin/zfs load-key "${d.name}"; then
                echo "zfs-unlock: Unlocked ${d.name}"
                break
              fi
              echo "zfs-unlock: Attempt $attempt failed for ${d.name}"
            done
          fi
        fi
      '')
      devices}

    # Verify unlock
    all_ok=1
    ${lib.concatMapStrings (d: ''
        if [[ "$(${zfs}/bin/zfs get -Ho value keystatus "${d.name}" 2>/dev/null)" == "unavailable" ]]; then
          echo "zfs-unlock: FATAL: ${d.name} still locked"
          all_ok=0
        fi
      '')
      devices}
    [[ "$all_ok" -eq 1 ]] || exit 1

    # Anti-replay: extend PCR 15 with zeros to invalidate credential
    echo "zfs-unlock: Anti-replay PCR 15 extension..."
    ${lib.concatMapStrings (bank: ''
        if ! ${tpm2_pcrextend} "15:${bank}=${pcrZerosForBank bank}" 2>&1; then
          echo "zfs-unlock: WARNING: Post-unlock PCR extend failed for bank ${bank}"
        fi
      '')
      usedBanks}
  '';
in {
  options.zfsUnlock = {
    enable = lib.mkEnableOption "TPM2-based ZFS unlock with filesystem confusion attack protection";
    espDevice = lib.mkOption {
      type = lib.types.str;
      default = config.fileSystems.${config.boot.loader.efi.efiSysMountPoint}.device;
      defaultText = lib.literalExpression "config.fileSystems.\${efiSysMountPoint}.device";
      description = ''
        Block device the initrd mounts to reach the credentials.

        Defaults to whatever mounts the ESP in stage 2, which is the only
        correct source of truth. It was briefly hardcoded to
        /dev/disk/by-partlabel/ESP on the assumption that disko labels a GPT
        partition with its bare attribute name -- it does not, it prefixes the
        disk: the real label is disk-main-ESP. Back when this was a systemd
        mount unit, that mismatch made the device unit wait out its 90s timeout,
        fail efi.mount, and take zfs-tpm-unlock.service down with it, so the
        pool never unlocked. Deriving it cannot drift from disko again, and it
        follows automatically if a host renames its disk attribute.
      '';
    };

    espMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/efi";
      description = "Where the INITRD mounts the ESP (read-only), created by the unlock script on demand and unmounted again as soon as the credentials are read. Deliberately not /boot: /boot is where stage 2 mounts the same partition, and keeping the names distinct stops the two from being confused when reading logs.";
    };

    credentialSubdir = lib.mkOption {
      type = lib.types.str;
      default = "zfs-unlock";
      description = "Directory under the ESP holding <dataset>.cred. In the booted system that is /boot/<this>, which is what zfs-key-sync.service writes to.";
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.pcrBank = lib.mkOption {
            type = lib.types.enum [
              "sha1"
              "sha256"
              "sha384"
              "sha512"
            ];
            default = "sha256";
            description = "TPM PCR bank the credential is sealed against. Must match what mkzfscreds used (it defaults to sha256). Previously sniffed out of the credential file at eval time; declaring it is what lets the credential live off-store.";
          };
        }
      );
      default = {};
      description = "ZFS datasets for PCR 15 fingerprint extension and optional TPM unlock. A dataset with no credential on the ESP simply falls through to the password prompt -- that is the bootstrap state, and it needs no rebuild to leave.";
      example = lib.literalExpression "{ rpool = { }; }";
    };
  };

  config = lib.mkIf (cfg.enable && devices != []) {
    assertions =
      map (d: {
        assertion =
          lib.any (
            fs: fs.fsType == "zfs" && (fs.device == d.name || lib.hasPrefix "${d.name}/" fs.device)
          )
          config.system.build.fileSystems;
        message = "zfs-unlock: Device '${d.name}' has no matching ZFS filesystem.";
      })
      devices;

    # `just seal-zfs-cred` tells the operator to run `zfs-fingerprint` as a
    # plain command inside the VM, so it has to be on PATH. The initrd only
    # ever invokes it by absolute store path, which is why this was missed.
    environment.systemPackages = [zfsFingerprint.bin];

    boot.zfs.requestEncryptionCredentials = lib.mkDefault false;

    # vfat + every NLS table it might ask for, force-loaded into the initrd.
    #
    # kernelModules (force-load), NOT availableKernelModules: the latter only
    # makes a module *available* for something to trigger, and udev triggers on
    # hardware matches, which a filesystem never produces.
    #
    # This is what the ESP mount actually died on, and the mount(8) message named
    # it: "wrong fs type, bad option, bad superblock ... missing codepage". Note
    # what it is NOT -- a missing vfat module gives the distinct "unknown
    # filesystem type 'vfat'". This was EINVAL from a vfat that HAD loaded.
    #
    # fs/fat always does load_nls() for the on-disk codepage to read 8.3 short
    # names, and load_nls() falls back to request_module() when the table is not
    # already registered. That request cannot resolve in the initrd, so vfat
    # returns EINVAL. Stage 2 mounts the same partition fine because autoload
    # there has the full module tree -- which is exactly why this looked like a
    # bad superblock when the filesystem was perfectly healthy.
    #
    # All four tables, not just this kernel's: which one fat asks for depends on
    # CONFIG_FAT_DEFAULT_CODEPAGE / _IOCHARSET / _UTF8, compiled per kernel. This
    # kernel (cachyos 7.0.9) is 437 + "ascii" + UTF8=y, so it needs nls_cp437 and
    # nothing else -- but dellvis and jarvis may not run this kernel, and a
    # different default silently reintroduces the same EINVAL. Four modules is a
    # few KB of initrd; rediscovering this from "bad superblock" is an evening.
    boot.initrd.kernelModules = [
      "vfat"
      "nls_cp437"
      "nls_iso8859-1"
      "nls_ascii"
      "nls_utf8"
    ];

    boot.initrd.systemd = {
      enable = true;
      tpm2.enable = true;

      # No mounts = [ ... ] entry: the ESP is mounted by the unlock script
      # itself. See the header section on why the efi.mount unit was removed
      # rather than debugged further.
      #
      # The credential is read from the ESP rather than injected into the initrd
      # via boot.initrd.secrets. See the header: lzbt skips reinstall when the
      # generation is already installed, so an initrd-embedded credential is
      # only refreshed by a NEW generation -- which a self-service re-seal does
      # not produce.
      storePaths =
        [
          tpm2_pcrextend
          unlockScript
          systemd-creds
          systemd-ask-password
          # mount/umount/mkdir are invoked by absolute store path from the unlock
          # script, so they must be pulled in explicitly -- the initrd's own
          # /bin/mount exists for systemd's mount units, and relying on it would
          # be relying on an implementation detail of a mechanism we just stopped
          # using.
          mount
          umount
          mkdir
          # Password agent for console prompts
          "${config.boot.initrd.systemd.package}/bin/systemd-tty-ask-password-agent"
        ]
        ++ zfsFingerprint.storePaths;

      services.zfs-tpm-unlock = {
        description = "ZFS TPM2 unlock with PCR 15 fingerprint extension";
        # Run after ZFS pools are imported
        after = ["zfs-import.target"];
        # Must complete before root filesystem mount
        before = [
          "sysroot.mount"
          "initrd-root-fs.target"
        ];
        wantedBy = ["sysroot.mount"];
        # Prevent starting during switch-root
        conflicts = ["initrd-switch-root.target"];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = toString unlockScript;
      };
    };
  };
}
