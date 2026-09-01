#!/usr/bin/env bash
# `dev [<cell>]` -- switch which cell's devshell direnv loads.
#
# Wrapped as a writeShellApplication and put on PATH in every cell's devshell
# (see cells/*/devshells.nix). A PATH binary, NOT a shellHook function, because
# direnv marshals env VARS (incl. PATH) into the interactive shell but not shell
# FUNCTIONS -- a hook-defined `dev` never reaches zsh, a PATH binary does. The
# tradeoff: a child process cannot cd its parent, so this prints the target dir
# rather than cd'ing. It writes the chosen cell to .ren/devshell (read by the
# root .envrc) and reloads direnv, so the new environment layers into the
# current shell on the next prompt. `dev` with no arg returns to repo.
#
# Shared here rather than duplicated per cell so `dev` also exists in a service
# shell to switch back.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cells="$root/cells"
cell="${1:-repo}"

if [ "$cell" != "repo" ] && [ ! -e "$cells/$cell/devshells.nix" ]; then
  echo "dev: no devshell in cell '$cell' ($cells/$cell/devshells.nix missing)" >&2
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

# Re-reads .envrc (which use-ren's the selected cell); direnv's shell hook
# applies the new env on the next prompt.
direnv reload >/dev/null 2>&1 || true

echo "dev: selected '$cell'." >&2
# NOT a cd (a child cannot cd its parent). Print the dir so the caller may
# `cd "$(dev hisilome)"`; service configs use relative paths from the cell dir.
printf '%s\n' "$dest"
