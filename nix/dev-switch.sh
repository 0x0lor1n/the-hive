# The `dev` devshell switcher, sourced into every cell's shellHook so the
# function exists in whichever shell is active -- including to switch BACK from
# a service shell to the deploy shell.
#
# It is a shell FUNCTION, not a packaged binary, for one reason: it must `cd`
# the interactive shell into the target cell, and a child process cannot change
# its parent's cwd. It writes the chosen cell to .ren/devshell (read by .envrc),
# cd's, then `direnv reload` re-enters via the rensa direnv integration -- so
# the environment layers into the current shell (zsh stays zsh) and rensa's
# watches/gcroots are preserved.
#
#   dev            -> deploy shell (repo), cd repo root
#   dev hisilome   -> site+radio shell, cd cells/hisilome
dev() {
  local root cells cell dest
  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "dev: not in a git repo" >&2
    return 1
  }
  cells="$root/cells"
  cell="${1:-repo}"

  if [ "$cell" != "repo" ] && [ ! -e "$cells/$cell/devshells.nix" ]; then
    echo "dev: no devshell in cell '$cell' ($cells/$cell/devshells.nix missing)" >&2
    echo "available:" >&2
    echo "  dev            the deploy shell (repo)" >&2
    local d c
    for d in "$cells"/*/devshells.nix; do
      [ -e "$d" ] || continue
      c=$(basename "$(dirname "$d")")
      [ "$c" = "repo" ] && continue
      echo "  dev $c" >&2
    done
    return 1
  fi

  # repo's shell is the root; a service cell's shell wants its own dir, where
  # its relative-path configs (process-compose, zola) resolve.
  if [ "$cell" = "repo" ]; then
    dest="$root"
  else
    dest="$cells/$cell"
  fi

  mkdir -p "$root/.ren"
  echo "$cell" >"$root/.ren/devshell"
  echo "dev: selected '$cell' -- cd $dest, reloading direnv."
  cd "$dest" || return 1
  direnv reload
}
