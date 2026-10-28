# Initrd ZFS unlock: PCR 15 extended with the pool fingerprint before unseal, with zeros after.
# Credentials are read from the ESP at runtime: lanzaboote never rewrites a UKI whose generation exists.
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

  # Mounted here, not by an initrd mount unit: that unit failed with mount exit 32.
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

  umountEspFn = ''
    unmount_esp() {
      if [[ "$esp_mounted" -eq 1 ]]; then
        ${umount} ${cfg.espMountPoint} || echo "zfs-unlock: WARNING: could not unmount ${cfg.espMountPoint}"
        esp_mounted=0
      fi
    }
  '';

  # `devices` is non-empty (config guard), so shellDryRun never sees an empty `then`.
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

    ${mountEsp}
    ${tpmUnlockSection}
    unmount_esp

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

    all_ok=1
    ${lib.concatMapStrings (d: ''
        if [[ "$(${zfs}/bin/zfs get -Ho value keystatus "${d.name}" 2>/dev/null)" == "unavailable" ]]; then
          echo "zfs-unlock: FATAL: ${d.name} still locked"
          all_ok=0
        fi
      '')
      devices}
    [[ "$all_ok" -eq 1 ]] || exit 1

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
      # disko prefixes partlabels with the disk name (disk-main-ESP), so never hardcode one.
      description = "Block device the initrd mounts to reach the credentials.";
    };

    espMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/efi";
      description = "Where the initrd mounts the ESP read-only while reading credentials; distinct from stage 2's /boot.";
    };

    credentialSubdir = lib.mkOption {
      type = lib.types.str;
      default = "zfs-unlock";
      description = "Directory under the ESP holding <dataset>.cred; zfs-key-sync writes /boot/<this>.";
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
            description = "TPM PCR bank the credential is sealed against; must match mkzfscreds.";
          };
        }
      );
      default = {};
      description = "ZFS datasets to fingerprint into PCR 15; without a credential on the ESP they fall back to the password prompt.";
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

    # On PATH for `just seal-zfs-cred`; the initrd uses the store path.
    environment.systemPackages = [zfsFingerprint.bin];

    boot.zfs.requestEncryptionCredentials = lib.mkDefault false;

    # fat calls load_nls() and request_module() can't resolve in the initrd: EINVAL "missing codepage".
    # All four tables: the default codepage is a per-kernel CONFIG_FAT_DEFAULT_* choice.
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

      storePaths =
        [
          tpm2_pcrextend
          unlockScript
          systemd-creds
          systemd-ask-password
          mount
          umount
          mkdir
          "${config.boot.initrd.systemd.package}/bin/systemd-tty-ask-password-agent"
        ]
        ++ zfsFingerprint.storePaths;

      services.zfs-tpm-unlock = {
        description = "ZFS TPM2 unlock with PCR 15 fingerprint extension";
        after = ["zfs-import.target"];
        before = [
          "sysroot.mount"
          "initrd-root-fs.target"
        ];
        wantedBy = ["sysroot.mount"];
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
