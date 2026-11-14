# ZFS encryption + PCR 15 gate. With no credential the boot asks for the
# passphrase and zfs-key-sync seals one.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  config,
  ...
}: let
  mkcreds = inputs.mkcreds.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Wraps the whole sealing dance (fingerprint -> predict PCR 15 -> seal).
  mkzfscreds = import ./__mkzfscreds.nix {
    inherit pkgs credDir;
    defaultPcrIds = pcrIds;
    zfsPackage = config.boot.zfs.package;
    mkcredsPackage = mkcreds;
  };

  zfsFingerprint = import ./__zfs-fingerprint.nix {
    inherit pkgs;
    zfsPackage = config.boot.zfs.package;
  };

  # Where zfs-key-sync writes the credential in the booted system. The initrd
  # reads the same file through its own read-only mount of the ESP at
  # zfsUnlock.espMountPoint -- see hardware-zfs-unlock.nix.
  credDir = "${config.boot.loader.efi.efiSysMountPoint}/${config.zfsUnlock.credentialSubdir}";

  secretPath = config.zfsUnlock.passphraseFile;
  pcrIds = config.zfsUnlock.pcrIds;
  sealsPcr7 = lib.elem "7" (lib.splitString "," pcrIds);
in {
  # The passphrase the pool is rotated to and the credential sealed from. null
  # (no secrets profile) means zfs-key-sync is not installed at all: the pool
  # keeps its disko-time key and the operator seals by hand with
  # `mkzfscreds --devices rpool > /boot/zfs-unlock/rpool.cred`.
  options.zfsUnlock.passphraseFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Runtime path of the rpool passphrase; null disables zfs-key-sync.";
  };

  # 0-7 are firmware PCRs: a host opts in only where it owns the firmware or
  # the Secure Boot keys, since every change there means a reseal.
  options.zfsUnlock.pcrIds = lib.mkOption {
    type = lib.types.strMatching "([0-9]+,)*15(,[0-9]+)*";
    default = "15";
    description = "Comma-separated PCRs the rpool credential is sealed to; must include 15.";
  };

  config = {
    # systemd initrd is the only initrd in this nixpkgs (scripted one is
    # gone; `boot.initrd.systemd.enable` is a removed option).
    boot.initrd.systemd.tpm2.enable = true;

    boot.initrd.availableKernelModules = [
      "tpm_crb"
      "tpm_tis"
    ];

    zfsUnlock.enable = true;
    # No credentialFile: the credential is found on the ESP at runtime. Absent
    # means "prompt", which is the bootstrap state.
    zfsUnlock.devices.rpool = {};

    # The marker below records a sha256 of the passphrase, so it stays inside the
    # encrypted pool rather than next to the credential on the unencrypted ESP.
    environment.persistence."/persist".directories = [
      {
        directory = "/var/lib/zfs-unlock";
        mode = "0700";
      }
    ];

    systemd.services.zfs-key-sync = lib.mkIf (secretPath != null) {
      description = "Sync rpool's key to the agenix secret and re-seal the TPM credential";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      unitConfig.RequiresMountsFor = [
        config.boot.loader.efi.efiSysMountPoint
        "/persist"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        config.boot.zfs.package
        mkzfscreds
        zfsFingerprint.bin
        pkgs.coreutils
        pkgs.gawk
        pkgs.tpm2-tools
      ];
      script = ''
        set -uo pipefail

        SECRET=${lib.escapeShellArg secretPath}
        CRED_DIR=${lib.escapeShellArg credDir}
        MARKER=/var/lib/zfs-unlock/key-gen
        POOL=rpool

        # Fail safe, not closed: with no secret the pool keeps whatever key it
        # has and the boot still works via prompt or an existing credential.
        # This is the normal state on a fresh image, where agenix cannot
        # decrypt until the real SSH host key is captured (see secrets.nix).
        if [ ! -r "$SECRET" ]; then
          echo "zfs-key-sync: no readable secret at $SECRET; leaving the pool key alone"
          exit 0
        fi
        pw=$(cat "$SECRET")
        if [ -z "$pw" ]; then
          echo "zfs-key-sync: secret is empty; refusing to rotate to an empty key"
          exit 0
        fi

        secret_hash=$(printf '%s' "$pw" | sha256sum | cut -d' ' -f1)
        fp_now=$(zfs-fingerprint "$POOL" sha256) || {
          echo "zfs-key-sync: cannot fingerprint $POOL"; exit 1; }
        ids_now=${lib.escapeShellArg pcrIds}
        pcr7_now=-
        ${lib.optionalString sealsPcr7 ''
          pcr7_now=$(tpm2_pcrread -T device:/dev/tpmrm0 sha256:7 2>/dev/null | awk '$1 == "7" {print $3}')
          [ -n "$pcr7_now" ] || { echo "zfs-key-sync: cannot read PCR 7"; exit 1; }
        ''}
        have_hash=$(awk '{print $1}' "$MARKER" 2>/dev/null || true)
        have_fp=$(awk '{print $2}' "$MARKER" 2>/dev/null || true)
        have_ids=$(awk '{print $3}' "$MARKER" 2>/dev/null || true)
        have_pcr7=$(awk '{print $4}' "$MARKER" 2>/dev/null || true)

        if [ "$secret_hash" = "$have_hash" ] && [ "$fp_now" = "$have_fp" ] \
            && [ "$ids_now" = "$have_ids" ] && [ "$pcr7_now" = "$have_pcr7" ]; then
          echo "zfs-key-sync: already in sync"
          exit 0
        fi
        ${lib.optionalString sealsPcr7 ''
          # Sealing on an SB-off or Setup Mode boot would bind PCR 7 to that state.
          efivar() {
            od -An -tu1 -j4 -N1 /sys/firmware/efi/efivars/"$1"-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | tr -d ' '
          }
          if [ "$(efivar SecureBoot)" != 1 ] || [ "$(efivar SetupMode)" != 0 ]; then
            echo "zfs-key-sync: Secure Boot not on in User Mode; not sealing to PCR 7, credential left as is"
            exit 0
          fi
        ''}
        if [ "$(zfs get -Ho value keystatus "$POOL")" != "available" ]; then
          echo "zfs-key-sync: $POOL key not loaded; cannot rotate"
          exit 1
        fi

        if [ "$secret_hash" != "$have_hash" ]; then
          echo "zfs-key-sync: rotating $POOL to the agenix passphrase"
          # Two lines: passphrase + confirmation. Measured to work on non-TTY
          # stdin, and the resulting key is the single value, not the pair.
          if ! printf '%s\n%s\n' "$pw" "$pw" \
              | zfs change-key -o keyformat=passphrase -o keylocation=prompt "$POOL"; then
            echo "zfs-key-sync: change-key failed; pool keeps its previous key"
            exit 1
          fi
          # change-key recomputes DSL_CRYPTO_MAC, so the fingerprint just moved.
          # Re-read it, or the marker would store a stale value and this service
          # would rotate again on every boot.
          fp_now=$(zfs-fingerprint "$POOL" sha256) || {
            echo "zfs-key-sync: cannot re-fingerprint after rotation"; exit 1; }
        fi

        echo "zfs-key-sync: sealing credential to PCRs $ids_now (PCR 15 of the next boot)"
        install -d -m 0700 "$CRED_DIR"
        if ! mkzfscreds --devices "$POOL" --name "$POOL" \
            --passphrase-file "$SECRET" > "$CRED_DIR/$POOL.cred.new"; then
          echo "zfs-key-sync: sealing failed; leaving any previous credential in place"
          rm -f "$CRED_DIR/$POOL.cred.new"
          exit 1
        fi
        mv -f "$CRED_DIR/$POOL.cred.new" "$CRED_DIR/$POOL.cred"

        install -d -m 0700 /var/lib/zfs-unlock
        printf '%s %s %s %s' "$secret_hash" "$fp_now" "$ids_now" "$pcr7_now" > "$MARKER"
        chmod 0600 "$MARKER"
        echo "zfs-key-sync: done; next boot should unlock silently"
      '';
    };

    # mkcreds seals a systemd credential against a predicted future PCR value
    # (systemd-creds encrypt cannot do this, systemd#38763). Sealing must run
    # inside the target machine: it binds to that TPM's own SRK.
    environment.systemPackages = [
      mkzfscreds
      mkcreds
      pkgs.tpm2-tools
    ];
  };
}
