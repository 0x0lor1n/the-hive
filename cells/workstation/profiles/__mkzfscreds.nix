# Seals a ZFS passphrase into a systemd credential bound to the PCR 15 value
# that hardware-zfs-unlock.nix will produce on the NEXT boot. Replaces the
# hand-typed `just seal-zfs-cred` runbook: one command instead of an operator
# retyping a hex pipeline, with the fingerprint and PCR prediction computed
# in-process.
#
# Derived from shinasada/nix-config (modules/apps/mkzfscreds/flake-parts.nix),
# itself built on codgician/mkcreds. Upstream is a flake-parts `perSystem`
# module; this repo must not retreat to flake-parts (AGENTS.md), so the shell
# body is lifted into a plain function returning the package.
#
# Three deliberate divergences from upstream, each documented below at its own
# call site: the default PCR set, how the PCR spec string is built, and passing
# mkcreds --name (without which nothing this produces can ever be decrypted by
# hardware-zfs-unlock.nix).
#
# `__` prefix keeps the profiles/default.nix loader from picking this up as a profile —
# it's a plain function, not a NixOS module. See profiles/default.nix.
{
  pkgs,
  zfsPackage,
  mkcredsPackage,
  # Where the booted system must place the credential for the initrd to find
  # it (e.g. "/boot/zfs-unlock"). Passed in rather than hardcoded so the tool
  # PRINTS the real destination: the previous closing message told the operator
  # to set zfsUnlock.devices.<pool>.credentialFile and rebuild, which had
  # already been deleted when the credential moved to the ESP. Instructions in
  # a separate file go stale silently; a value derived from the config cannot.
  credDir,
}: let
  zfsFingerprint = import ./__zfs-fingerprint.nix {
    inherit pkgs zfsPackage;
  };

  mkcredsBin = "${mkcredsPackage}/bin/mkcreds";

  # Divergence 1: upstream defaults to "0,1,2,3,5,7,15". We default to PCR 15
  # alone, which is what hardware-zfs-unlock.nix measures and what the manual
  # runbook always sealed against. Broadening to include firmware and Secure
  # Boot state (0-7) is strictly stronger but strictly more brittle — a
  # firmware or kernel update moves those PCRs, the credential stops
  # unsealing, and the operator is back at the passphrase prompt needing a
  # re-seal. That is a threat-model change and gets its own decision, not a
  # silent default. Pass --pcr-ids to opt in per invocation.
  defaultPcrIds = "15";
in
  pkgs.writeShellApplication {
    name = "mkzfscreds";
    runtimeInputs = with pkgs; [
      coreutils
      openssl
      tpm2-tools
      xxd
    ];
    text = ''
      set -euo pipefail

      err() { echo "Error: $*" >&2; exit 1; }
      log() { echo "$*" >&2; }

      show_help() {
        # Quoted delimiter: the help text is literal, and must stay literal --
        # unquoted, shellcheck reads the backticks below as command substitution
        # (SC2006) and writeShellApplication fails the build. The default-PCR
        # value below is Nix-interpolated, so it is already literal here.
        cat >&2 <<'EOF'
      mkzfscreds - seal a ZFS passphrase against the PCR 15 value of the next boot

      USAGE: mkzfscreds --devices <dataset>... > output.cred

      OPTIONS:
        -h, --help        Show this help
        --devices DEVS    Space-separated ZFS datasets to fingerprint (required)
        --name NAME       Credential name (default: the first dataset). MUST equal
                          the zfsUnlock.devices.<name> attribute -- the unlock
                          path decrypts with --name= and systemd-creds refuses a
                          credential whose embedded name differs.
        --pcr-ids IDS     Comma-separated PCR IDs (default: ${defaultPcrIds})
        --print-pcr15     Print the expected PCR 15 and exit without sealing
        --passphrase-file F
                          Read the passphrase from F instead of prompting, for
                          unattended use (zfs-key-sync.service). Trailing
                          newlines are stripped, so F must hold the same bytes
                          `zfs change-key` was given -- see the note in
                          profiles/secrets.nix about generating without one.

      Must run inside the target machine, as root: zdb needs raw device access
      and the TPM seals against its own SRK, so a credential made elsewhere is
      useless here. The credential goes to stdout; redirect it to a file.

      Dataset order is significant: PCR 15 is extended once per dataset, in the
      order given, and must match the order hardware-zfs-unlock.nix uses at boot
      (its zfsUnlock.devices attribute order).
      EOF
      }

      # PCR extend, in software: PCR_next = SHA256(PCR_current || digest), with
      # PCR 15 starting at 32 zero bytes on every boot. Mirrors the single
      # tpm2_pcrextend per dataset that hardware-zfs-unlock.nix performs before
      # it attempts the unseal.
      compute_expected_pcr15() {
        local pcr fp
        pcr=$(printf '%064d' 0)
        for dev in "$@"; do
          if ! fp=$(${zfsFingerprint.script} "$dev" sha256); then
            err "Fingerprint computation failed for $dev"
          fi
          log "  $dev: $fp"
          pcr=$(echo -n "$pcr$fp" | xxd -r -p | openssl dgst -sha256 -binary | xxd -p -c256)
        done
        echo "$pcr"
      }

      pcr_ids="${defaultPcrIds}"
      print_only=0
      cred_name=""
      pass_file=""
      devices=()

      while [[ $# -gt 0 ]]; do
        case $1 in
          -h|--help) show_help; exit 0 ;;
          --name) cred_name="$2"; shift 2 ;;
          --passphrase-file) pass_file="$2"; shift 2 ;;
          --pcr-ids) pcr_ids="$2"; shift 2 ;;
          --print-pcr15) print_only=1; shift ;;
          --devices) shift; while [[ $# -gt 0 && "$1" != -* ]]; do devices+=("$1"); shift; done ;;
          -*) err "Unknown option: $1" ;;
          *) devices+=("$1"); shift ;;
        esac
      done

      [[ ''${#devices[@]} -gt 0 ]] || err "No devices specified. Use --devices."
      [[ ",$pcr_ids," =~ ,15, ]] || err "PCR 15 must be included in --pcr-ids"
      [[ -e /dev/tpm0 || -e /dev/tpmrm0 ]] || err "No TPM device found"

      # Divergence 3: upstream omits mkcreds --name entirely. That would be a
      # silent brick here -- hardware-zfs-unlock.nix decrypts with
      # `systemd-creds decrypt --name="<device>"`, and systemd-creds embeds the
      # name at encrypt time and refuses to decrypt a credential whose embedded
      # name differs. The old seal-zfs-cred runbook passed --name=rpool by hand;
      # this keeps that, defaulting to the first dataset.
      [[ -n "$cred_name" ]] || cred_name="''${devices[0]}"

      log "Creating credential for: ''${devices[*]}"
      log "Computing expected PCR 15..."
      expected_pcr15=$(compute_expected_pcr15 "''${devices[@]}")
      log "Expected PCR 15: $expected_pcr15"

      if [[ "$print_only" -eq 1 ]]; then
        echo "$expected_pcr15"
        exit 0
      fi

      # Divergence 2: upstream builds this with
      #   sed "s/,/+/g; s/15/15:sha256=$expected"
      # i.e. substring matching where field matching is meant. Tested against
      # every valid PCR list shape (ids are 0-23) and the two agree everywhere --
      # this is NOT fixing a reachable bug, and upstream is not broken. Splitting
      # on commas is just locally obvious rather than obvious-after-a-proof, and
      # it also behaves sanely on malformed input like "15,15", where the sed
      # substitutes only the first field.
      pcr_spec=""
      IFS=',' read -ra pcr_id_list <<< "$pcr_ids"
      for id in "''${pcr_id_list[@]}"; do
        [[ -n "$pcr_spec" ]] && pcr_spec+="+"
        if [[ "$id" == "15" ]]; then
          pcr_spec+="15:sha256=$expected_pcr15"
        else
          pcr_spec+="$id"
        fi
      done
      log "PCR specification: $pcr_spec"

      if [[ -n "$pass_file" ]]; then
        [[ -r "$pass_file" ]] || err "Cannot read passphrase file: $pass_file"
        # $(cat) strips ALL trailing newlines. zfs-key-sync.service reads the
        # same file the same way before piping to `zfs change-key`, so the two
        # cannot disagree; the generator also emits no trailing newline.
        secret=$(cat "$pass_file")
        log "Passphrase read from $pass_file"
      else
        read -s -r -p "Enter passphrase for ''${devices[0]}: " secret; echo >&2
      fi
      [[ -n "$secret" ]] || err "Passphrase cannot be empty"

      log "Sealing as credential name '$cred_name' with mkcreds"
      log "(systemd-creds cannot bind to a FUTURE pcr value, which is why mkcreds exists)..."
      echo -n "$secret" | ${mkcredsBin} --name="$cred_name" --tpm2-pcrs="$pcr_spec" - - \
        || err "Failed to create credential"

      log ""
      log "Done. Save it where the initrd actually looks:"
      log "  mkdir -p ${credDir}"
      log "  <this command> > ${credDir}/$cred_name.cred"
      log ""
      log "No rebuild needed -- the initrd mounts the ESP and reads it directly."
      log "Do NOT put it in the repo or on the 9p share; nothing reads it there."
    '';
  }
