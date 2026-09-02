# Native ZFS encryption + TPM2 pre-unseal gate. Enables zfsUnlock
# (hardware-zfs-unlock.nix) for the pre-unseal PCR 15 gate + anti-replay.
#
# Bootstrap needs no configuration and no rebuild: with no credential on
# the ESP the fingerprint still extends into PCR 15 every boot, the unseal
# is skipped, and the boot falls through to the ZFS passphrase prompt.
# zfs-key-sync.service below then seals one on first boot, and the next
# boot is silent.
#
# Two-level `{ inputs, cell }:` shape so the returned NixOS module can
# reference `inputs.mkcreds` below.
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

  # Wraps the whole sealing dance (fingerprint -> predict PCR 15 -> seal) that
  # `just seal-zfs-cred` used to print for the operator to retype.
  mkzfscreds = import ./__mkzfscreds.nix {
    inherit pkgs credDir;
    zfsPackage = config.boot.zfs.package;
    mkcredsPackage = mkcreds;
  };

  zfsFingerprint = import ./__zfs-fingerprint.nix {
    inherit pkgs;
    zfsPackage = config.boot.zfs.package;
  };

  # Where zfs-key-sync writes the credential in the BOOTED system. The initrd
  # reads the same file, but through its own read-only mount of the ESP at
  # zfsUnlock.espMountPoint -- see hardware-zfs-unlock.nix.
  credDir = "${config.boot.loader.efi.efiSysMountPoint}/${config.zfsUnlock.credentialSubdir}";

  secretPath = config.zfsUnlock.passphraseFile;
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

  config = {
    boot.initrd.systemd.enable = true;
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
      ];
      script = ''
        set -uo pipefail

        SECRET=${lib.escapeShellArg secretPath}
        CRED_DIR=${lib.escapeShellArg credDir}
        MARKER=/var/lib/zfs-unlock/key-gen
        POOL=rpool

        # Fail SAFE, not closed: with no secret the pool keeps whatever key it
        # has and the boot still works via prompt or an existing credential. This
        # is the normal state on a fresh image, where agenix cannot decrypt until
        # the real SSH host key is captured (see secrets.nix header).
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
        have_hash=$(awk '{print $1}' "$MARKER" 2>/dev/null || true)
        have_fp=$(awk '{print $2}' "$MARKER" 2>/dev/null || true)

        if [ "$secret_hash" = "$have_hash" ] && [ "$fp_now" = "$have_fp" ]; then
          echo "zfs-key-sync: already in sync"
          exit 0
        fi

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

        echo "zfs-key-sync: sealing credential for PCR 15 of the next boot"
        install -d -m 0700 "$CRED_DIR"
        if ! mkzfscreds --devices "$POOL" --name "$POOL" \
            --passphrase-file "$SECRET" > "$CRED_DIR/$POOL.cred.new"; then
          echo "zfs-key-sync: sealing failed; leaving any previous credential in place"
          rm -f "$CRED_DIR/$POOL.cred.new"
          exit 1
        fi
        mv -f "$CRED_DIR/$POOL.cred.new" "$CRED_DIR/$POOL.cred"

        install -d -m 0700 /var/lib/zfs-unlock
        printf '%s %s' "$secret_hash" "$fp_now" > "$MARKER"
        chmod 0600 "$MARKER"
        echo "zfs-key-sync: done; next boot should unlock silently"
      '';
    };

    # mkcreds seals a systemd credential against a PREDICTED future PCR
    # value (systemd-creds encrypt cannot do this, see systemd#38763);
    # tpm2-tools provides tpm2_pcrread for sanity-checking PCR state.
    # Sealing must run INSIDE the VM -- TPM sealing is bound to that
    # TPM's own SRK, so it cannot be done on the host.
    environment.systemPackages = [
      mkzfscreds
      mkcreds
      pkgs.tpm2-tools
    ];
  };
}
