# Vendored from codgician/serenitea-pot
# (modules/nixos/system/zfs-unlock/zfs-fingerprint.nix), which
# shinasada/nix-config also vendors as external-modules/zfs-fingerprint.nix.
#
# Derives a fingerprint from a LOCKED pool's on-disk crypto metadata:
# MOS object 1 -> root_dataset -> com.datto:crypto_key_obj ->
# DSL_CRYPTO_GUID + DSL_CRYPTO_MAC, hashed together. Readable via zdb
# WITHOUT the encryption key, which is the whole point: it lets
# hardware-zfs-unlock.nix extend PCR 15 BEFORE unsealing, so a swapped
# pool makes the TPM refuse to release the key at all.
#
# Divergence from upstream: absolute coreutils paths for the hash/cut
# binaries (upstream relies on them being on the initrd PATH), and no
# `pkgs == null` guard (upstream needs it for their eval context, we
# always pass pkgs).
#
# `__` prefix keeps haumea from loading this as a profile — it's a
# plain function, not a NixOS module. See profiles/default.nix.
{
  pkgs,
  zfsPackage,
}: let
  zdb = "${zfsPackage}/bin/zdb";
  grep = "${pkgs.gnugrep}/bin/grep";
  coreutils = pkgs.coreutils;

  script = pkgs.writeShellScript "zfs-fingerprint" ''
    set -euo pipefail

    # Usage: zfs-fingerprint <dataset> [bank]
    # Outputs fingerprint to stdout, errors to stderr

    dataset="''${1:?Usage: zfs-fingerprint <dataset> [bank]}"
    bank="''${2:-sha256}"
    pool=''${dataset%%/*}

    # zdb reads raw block devices, so this needs root. Without it zdb emits a
    # confusing 4-line cascade ("no pools found: some devices require root
    # privileges" -> "no matching pools" -> "can't open") that looks like a
    # missing/corrupt pool rather than a permissions problem.
    if [[ "$(${coreutils}/bin/id -u)" -ne 0 ]]; then
      echo "zfs-fingerprint: must run as root (zdb needs raw device access). Try: sudo -i" >&2
      exit 1
    fi

    # Step 1: Get root_dataset object ID from MOS directory (object 1)
    root_ds=$(${zdb} -ddddd "$pool" 1 \
      | ${grep} -oP -m1 'root_dataset = \K\d+') || true

    if [[ -z "$root_ds" ]]; then
      echo "zfs-fingerprint: Cannot find root_dataset for $pool" >&2
      exit 1
    fi

    # Step 2: Get crypto_key_obj from root_dataset's DSL directory
    crypto_obj=$(${zdb} -ddddd "$pool" "$root_ds" \
      | ${grep} -oP -m1 'com\.datto:crypto_key_obj = \K\d+') || true

    if [[ -z "$crypto_obj" ]]; then
      echo "zfs-fingerprint: No crypto key for $pool (not encrypted?)" >&2
      exit 1
    fi

    # Step 3: Get GUID and MAC from crypto object
    crypto_out=$(${zdb} -ddddd "$pool" "$crypto_obj")
    guid=$(echo "$crypto_out" | ${grep} -oP -m1 'DSL_CRYPTO_GUID = \K-?\d+') || true
    mac=$(echo "$crypto_out" | ${grep} -oP -m1 'DSL_CRYPTO_MAC = \K[0-9a-fA-F]+') || true

    if [[ -z "$guid" || -z "$mac" ]]; then
      echo "zfs-fingerprint: Missing GUID or MAC for $pool" >&2
      exit 1
    fi

    # Compute fingerprint: hash(guid || mac)
    echo -n "''${guid}''${mac}" \
      | "${coreutils}/bin/''${bank}sum" \
      | ${coreutils}/bin/cut -d' ' -f1
  '';
in {
  inherit script;

  # The same script exposed as a normal package with bin/zfs-fingerprint so it
  # can land on PATH in the booted system. The initrd calls `script` by its
  # absolute store path and does not need this, but the Appendix D sealing
  # dance runs `zfs-fingerprint` as a plain command inside the VM.
  bin = pkgs.runCommand "zfs-fingerprint-bin" {} ''
    mkdir -p "$out/bin"
    ln -s ${script} "$out/bin/zfs-fingerprint"
  '';

  storePaths = [
    script
    zdb
    grep
    coreutils
  ];
}
