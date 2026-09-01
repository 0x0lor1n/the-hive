#!/usr/bin/env bash
# Poll Icecast for the listener count of one mount and write a display string
# for the console's live region to include via SSI.
#
# Scoped to a single mount on purpose: with more than one mount Icecast's
# status-json "source" field becomes an array, so a naive '"listeners":' match
# would report whichever station happened to serialise first.
#
# Writes atomically (temp + rename) because nginx may read the file at any time.

set -euo pipefail

MOUNT="${MOUNT:-/stream.mp3}"
ADMIN="${ADMIN:-admin:hackme}"
HOST="${HOST:-127.0.0.1:8000}"
OUT="${OUT:-radio/state/listeners.txt}"
INTERVAL="${INTERVAL:-30}"
ONCE=0

[ "${1:-}" = "--once" ] && ONCE=1

# Extract <listeners> from within the <source mount="..."> block for our mount.
count_listeners() {
  curl -s --max-time 5 -u "$ADMIN" "http://${HOST}/admin/stats" 2>/dev/null |
    sed 's/</\n</g' |
    awk -v m="mount=\"$MOUNT\"" '
            index($0, m) { inmount = 1 }
            inmount && /^<\/source>/ { inmount = 0 }
            inmount && /^<listeners>/      { gsub(/^<listeners>/, "");      cur = $0 }
            inmount && /^<listener_peak>/  { gsub(/^<listener_peak>/, ""); peak = $0 }
            END { print cur "|" peak }
        '
}

render() {
  local n="${1%%|*}" peak="${1##*|}"
  # A counter reading 1 advertises emptiness. Below 2, say "connected"
  # instead - true at any count, and it reads as presence rather than census.
  if [ -n "$n" ] && [ "$n" -ge 2 ] 2>/dev/null; then
    printf '%s listening' "$n"
    [ -n "$peak" ] && [ "$peak" -gt "$n" ] 2>/dev/null && printf ' (peak %s)' "$peak"
  else
    printf 'connected'
  fi
}

write_once() {
  local n out tmp
  n="$(count_listeners || true)"
  out="$(render "$n")"
  tmp="${OUT}.tmp.$$"
  mkdir -p "$(dirname "$OUT")"
  printf '%s' "$out" >"$tmp"
  mv "$tmp" "$OUT"
}

if [ "$ONCE" -eq 1 ]; then
  write_once
  cat "$OUT"
  echo
  exit 0
fi

while true; do
  write_once || true
  sleep "$INTERVAL"
done
