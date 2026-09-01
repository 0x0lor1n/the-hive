#!/usr/bin/env bash
# ReplayGain track-gain tags, so liquidsoap reads ~4ms instead of analysing
# ~5s per track on a single core. EBU R128, target -18 LUFS (ReplayGain 2.0).
# Existing tags kept unless --force.

set -euo pipefail

TARGET="-18.0"
FORCE=0
DRY=0
DIR="music"

usage() {
  cat <<'USAGE'
tag-replaygain [options] [directory]

  Writes REPLAYGAIN_TRACK_GAIN into every audio file in <directory>
  (default: music). Already-tagged files are skipped.

Options:
  -t, --target LUFS   reference loudness (default -18.0)
  -f, --force         retag files that already carry a tag
  -n, --dry-run       measure and report, write nothing
  -h, --help          this text

Supported: .flac (metaflac), .m4a/.mp4 (ffmpeg), .mp3 (mid3v2, in place)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
  -t | --target)
    TARGET="$2"
    shift 2
    ;;
  -f | --force)
    FORCE=1
    shift
    ;;
  -n | --dry-run)
    DRY=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    echo "unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
  *)
    DIR="$1"
    shift
    ;;
  esac
done

if [ ! -d "$DIR" ]; then
  echo "not a directory: $DIR" >&2
  exit 1
fi

# Integrated loudness in LUFS, or empty if it could not be measured.
measure_lufs() {
  ffmpeg -nostdin -hide_banner -nostats -i "$1" -af ebur128 -f null - 2>&1 |
    awk '/Integrated loudness/{seen=1} seen && $1=="I:"{print $2; exit}'
}

# Current tag value, or empty. Case-insensitive: containers disagree on case.
read_tag() {
  ffprobe -v quiet -show_format -of default=noprint_wrappers=1 "$1" 2>/dev/null |
    awk -F= 'tolower($1)=="tag:replaygain_track_gain"{print $2; exit}'
}

write_tag() {
  local file="$1" value="$2" ext="$3" tmp
  case "$ext" in
  flac)
    metaflac --remove-tag=REPLAYGAIN_TRACK_GAIN \
      --set-tag="REPLAYGAIN_TRACK_GAIN=$value" "$file"
    ;;
  m4a | mp4)
    # MP4 has no standard ReplayGain field. Without use_metadata_tags
    # the mov muxer silently DROPS the tag - no error, no tag.
    tmp="$(dirname "$file")/.rgtmp.$$.$ext"
    ffmpeg -nostdin -hide_banner -loglevel error -y -i "$file" -c copy \
      -movflags use_metadata_tags \
      -metadata "replaygain_track_gain=$value" "$tmp"
    mv "$tmp" "$file"
    ;;
  mp3)
    # mid3v2 edits the ID3 tag in place. Do NOT remux mp3 with ffmpeg
    # -c copy: it rewrites the Xing/LAME header, losing encoder delay
    # and padding, which shifts the decoded audio (measured: +0.09s
    # and +1 frame per file). mid3v2 leaves the audio bit-identical.
    mid3v2 --TXXX "REPLAYGAIN_TRACK_GAIN:$value" "$file" >/dev/null
    ;;
  *)
    return 1
    ;;
  esac
}

tagged=0
skipped=0
failed=0
unsupported=0

while IFS= read -r -d '' file; do
  name="$(basename "$file")"
  ext="${name##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
  flac | m4a | mp4 | mp3) ;;
  *)
    printf '  SKIP  %-52s unsupported (.%s)\n' "${name:0:52}" "$ext"
    unsupported=$((unsupported + 1))
    continue
    ;;
  esac

  if [ "$FORCE" -eq 0 ] && [ -n "$(read_tag "$file")" ]; then
    printf '  have  %-52s %s\n' "${name:0:52}" "$(read_tag "$file")"
    skipped=$((skipped + 1))
    continue
  fi

  lufs="$(measure_lufs "$file")"
  if [ -z "$lufs" ]; then
    printf '  FAIL  %-52s could not measure\n' "${name:0:52}"
    failed=$((failed + 1))
    continue
  fi

  gain="$(awk -v i="$lufs" -v t="$TARGET" 'BEGIN{printf "%.2f dB", t - i}')"

  if [ "$DRY" -eq 1 ]; then
    printf '  dry   %-52s %8s LUFS -> %s\n' "${name:0:52}" "$lufs" "$gain"
    continue
  fi

  if ! write_tag "$file" "$gain" "$ext"; then
    printf '  FAIL  %-52s write failed\n' "${name:0:52}"
    failed=$((failed + 1))
    continue
  fi

  # Read back. MP4 in particular will accept a write and store nothing.
  if [ -z "$(read_tag "$file")" ]; then
    printf '  FAIL  %-52s tag did not survive write\n' "${name:0:52}"
    failed=$((failed + 1))
    continue
  fi

  printf '  tag   %-52s %8s LUFS -> %s\n' "${name:0:52}" "$lufs" "$gain"
  tagged=$((tagged + 1))
done < <(find "$DIR" -maxdepth 1 -type f -print0 | sort -z)

echo
echo "  tagged: $tagged   already tagged: $skipped   failed: $failed   unsupported: $unsupported"
[ "$failed" -eq 0 ]
