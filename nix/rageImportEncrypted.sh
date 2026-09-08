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
  # age-plugin-tpm asks for the PIN on /dev/tty itself, so a cache miss during
  # an interactive `nix build`/`nixos-rebuild` simply prompts (oddlama-style).
  # Only when there is no controlling tty (agents, CI, sudo without a tty) does
  # this fail — then say what to do instead of dumping a rage trace.
  if ! rage --decrypt "${args[@]}" --output "$out" "$file"; then
    rm -f "$out"
    if ! { : </dev/tty; } 2>/dev/null; then
      echo "secrets: no cached plaintext for $(basename "$file") (UID $UID) and no tty to ask the TPM PIN on." >&2
      echo '  run `unlock-secrets` from an interactive shell (same user, no sudo), then retry.' >&2
    fi
    exit 1
  fi
fi

cat "$out"
