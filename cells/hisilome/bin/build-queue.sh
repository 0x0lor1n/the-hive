#!/usr/bin/env bash
# Build a deterministic play queue so the console can show a schedule.
#
# playlist(mode="randomize") decides lazily - liquidsoap prepares one track
# ahead, so there is no future to display. Writing the order out in advance and
# playing it with mode="normal" is what makes "in 8 mins" possible at all.
#
# Emits two files, in the same order, written atomically:
#   queue.m3u  one path per line          (consumed by liquidsoap's playlist)
#   queue.tsv  "<seconds>\t<path>\t<album>"  (consumed by the schedule writer)
#
# Durations come from ffprobe here so the schedule never has to decode anything
# at render time. Several shuffled rounds are concatenated because a single
# round of a small library runs out in a few hours; liquidsoap would then loop
# the identical order.

set -euo pipefail

DIR="${DIR:-music}"
OUT="${OUT:-radio/state}"
ROUNDS="${ROUNDS:-4}"
SEED="${SEED:-}"

while [ $# -gt 0 ]; do
  case "$1" in
  -r | --rounds)
    ROUNDS="$2"
    shift 2
    ;;
  -o | --out)
    OUT="$2"
    shift 2
    ;;
  -s | --seed)
    SEED="$2"
    shift 2
    ;;
  -h | --help)
    echo "build-queue [--rounds N] [--out DIR] [--seed N] [directory]"
    exit 0
    ;;
  -*)
    echo "unknown option: $1" >&2
    exit 2
    ;;
  *)
    DIR="$1"
    shift
    ;;
  esac
done

[ -d "$DIR" ] || {
  echo "not a directory: $DIR" >&2
  exit 1
}
mkdir -p "$OUT"

# Probe once, reuse for every round.
probe="$(mktemp)"
trap 'rm -f "$probe" "$probe.shuf"' EXIT

count=0
while IFS= read -r -d '' f; do
  # One probe for both. Album comes from the tag, not the filename, so
  # bin/tag-album stays the only thing deciding what a work is called.
  meta="$(ffprobe -v quiet -show_entries format=duration:format_tags=album \
    -of default=noprint_wrappers=1 "$f" 2>/dev/null || true)"
  d="$(printf '%s\n' "$meta" | awk -F= '$1=="duration"{print $2; exit}')"
  # containers disagree on tag case
  alb="$(printf '%s\n' "$meta" |
    awk 'tolower($0) ~ /^tag:album=/ {print substr($0, index($0, "=") + 1); exit}')"
  # skip anything ffprobe cannot read rather than poisoning the schedule
  case "$d" in
  '' | N/A)
    echo "  skip (no duration): $(basename "$f")" >&2
    continue
    ;;
  esac
  alb="${alb//$'\t'/ }" # a tab would invent a column
  # Appended, not inserted: the path stays field 2, so an older liquidsoap
  # still parses this file correctly.
  printf '%.0f\t%s\t%s\n' "$d" "$f" "$alb" >>"$probe"
  count=$((count + 1))
done < <(find "$DIR" -maxdepth 1 -type f -print0 | sort -z)

[ "$count" -gt 0 ] || {
  echo "no playable files in $DIR" >&2
  exit 1
}

tmp_m3u="$OUT/.queue.m3u.$$"
tmp_tsv="$OUT/.queue.tsv.$$"
: >"$tmp_m3u"
: >"$tmp_tsv"

for _round in $(seq 1 "$ROUNDS"); do
  if [ -n "$SEED" ]; then
    shuf --random-source=<(yes "$SEED") "$probe" >"$probe.shuf"
  else
    shuf "$probe" >"$probe.shuf"
  fi
  cut -f2 "$probe.shuf" >>"$tmp_m3u"
  cat "$probe.shuf" >>"$tmp_tsv"
done

# Atomic: liquidsoap watches queue.m3u and would happily load a half-written one
mv "$tmp_m3u" "$OUT/queue.m3u"
mv "$tmp_tsv" "$OUT/queue.tsv"

total="$(awk -F'\t' '{s+=$1} END{printf "%.1f", s/3600}' "$OUT/queue.tsv")"
echo "  queue: $count tracks x $ROUNDS rounds = $(wc -l <"$OUT/queue.m3u") entries, ${total}h"
