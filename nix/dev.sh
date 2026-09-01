#!/usr/bin/env bash
# dev [<cell>] -- select which cell's devshell .envrc loads, then reload direnv.
#
# A PATH binary rather than a shellHook function: direnv marshals env vars
# (incl. PATH) into the interactive shell, not functions. A child cannot cd its
# parent, so the target dir is printed instead: cd "$(dev hisilome)".
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cells="$root/cells"
cell="${1:-repo}"

if [ "$cell" != "repo" ] && [ ! -e "$cells/$cell/devshells.nix" ]; then
  echo "dev: no devshell in cell '$cell'" >&2
  echo "available:" >&2
  echo "  dev            the deploy shell (repo)" >&2
  for d in "$cells"/*/devshells.nix; do
    [ -e "$d" ] || continue
    c=$(basename "$(dirname "$d")")
    [ "$c" = "repo" ] && continue
    echo "  dev $c" >&2
  done
  exit 1
fi

if [ "$cell" = "repo" ]; then
  dest="$root"
else
  dest="$cells/$cell"
fi

mkdir -p "$root/.ren"
printf '%s\n' "$cell" > "$root/.ren/devshell"
direnv reload >/dev/null 2>&1 || true

echo "dev: selected '$cell'." >&2
printf '%s\n' "$dest"
