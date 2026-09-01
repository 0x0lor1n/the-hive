#!/usr/bin/env bash
# Decrypt an age-encrypted .nix file, caching the plaintext so repeated
# evaluations do not re-exercise the identity.
#
# Ported from ~/nixos-config/flake/rageImportEncrypted.sh, itself forked from
# oddlama/nix-config's rage-decrypt-and-cache.sh.
#
# NOTE the cache is PLAINTEXT ON DISK at /var/tmp/nix-import-encrypted/$UID/
# and is never cleared. Protection is "not in git", not "not on disk".
set -euo pipefail

file="$1"
shift
identities=("$@")

# Strip .age suffix, and store path prefix or ./ if applicable
basename="${file%".age"}"
[[ $file == "/nix/store/"* ]] && basename="${basename#*"-"}"
[[ $file == "./"* ]] && basename="${basename#"./"}"

# Content-based identifier, so relocating the source file in the nix store
# does not invalidate the cache.
new_name="$(sha512sum "$file")"
new_name="${new_name:0:32}-${basename//"/"/"_"}"

out="/var/tmp/nix-import-encrypted/$UID/$new_name"
umask 077
mkdir -p "$(dirname "$out")"

if [[ ! -e $out ]]; then
  args=()
  for i in "${identities[@]}"; do
    args+=("--identity" "$i")
  done
  rage --decrypt "${args[@]}" --output "$out" "$file"
fi

cat "$out"
