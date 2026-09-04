#!/usr/bin/env bash

# Forked from:
# https://github.com/oddlama/nix-config/blob/a3854ea1c1b253b1cf58d29a7eef799a6ce5a582/flake/rage-decrypt-and-cache.sh

set -euo pipefail

file="$1"
shift
identities=("$@")

# Cache key = content hash + plain basename, so the same ciphertext maps to the
# same cache entry whether it is addressed via the store (eval) or the checkout
# (`unlock-secrets` in the devshell, which primes this cache with a PIN identity).
basename="$(basename "${file%".age"}")"

new_name="$(sha512sum "$file")"
new_name="${new_name:0:32}-${basename}"

out="/var/tmp/nix-import-encrypted/$UID/$new_name"
umask 077
mkdir -p "$(dirname "$out")"

if [[ ! -e $out ]]; then
  args=()
  for i in "${identities[@]}"; do
    args+=("--identity" "$i")
  done
  # Never prompts: PIN-gated identities are used only by `unlock-secrets`,
  # which the user runs on purpose. Eval must not pop a PIN dialog.
  if ! rage --decrypt "${args[@]}" --output "$out" "$file" 2>/dev/null </dev/null; then
    rm -f "$out"
    echo "secrets: no cached plaintext for $(basename "$file") (UID $UID) and the quiet identities do not fit this TPM." >&2
    echo "  run \`unlock-secrets\` (same user, no sudo) to decrypt with this host's PIN identity, then retry." >&2
    exit 1
  fi
fi

cat "$out"
