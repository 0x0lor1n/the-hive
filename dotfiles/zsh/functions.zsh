# Real which
function rich() {
  realpath $(which -- "$@")
}

# Copy current command line to clipboard
function copybuffer() {
  printf "%s" "$BUFFER" | clipcopy
}
zle -N copybuffer

# Kill process on specified port
function killport() {
  local filter="( sport = :$1 )" out
  out=$(ss -Htulnp "$filter")
  # ss shows pid= only for sockets the caller owns.
  [[ -n $out && $out != *pid=* ]] && out=$(sudo ss -Htulnp "$filter")
  local -a pids=(${(u)${(M)${=${out//[,()]/ }}:#pid=*}#pid=})
  if (( ! $#pids )); then
    echo "No process found on port $1"
    return 1
  fi
  echo "Killing PIDs: $pids"
  kill -9 $pids 2>/dev/null || sudo kill -9 $pids
}
