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
  local pids=$(lsof -t -i:"$1" 2>/dev/null)
  if [[ -z "$pids" ]]; then
    echo "No process found on port $1"
    return 1
  fi
  echo "Killing PIDs: $pids"
  kill -9 $pids 2>/dev/null || sudo kill -9 $pids
}
