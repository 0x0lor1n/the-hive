#!/usr/bin/env bash
# Write ALBUM into every track, naming the work it came from: the game, the
# film, or the record. The console shows it under the track title.
#
# Taken from the filename's bracket prefix, since most of the library carries no
# tags: "[Silent Hill 2] - 28 Akira Yamaoka - Overdose Delusion.flac".
#
# Idempotent: already-tagged files are skipped unless --force.

set -euo pipefail

FORCE=0
DRY=0
DIR="music"

usage() {
  cat <<'USAGE'
tag-album [options] [directory]

  Writes ALBUM into every audio file in <directory> (default: music),
  derived from the [Bracket] prefix of the filename.
  Already-tagged files are skipped.

Options:
  -f, --force         retag files that already carry an ALBUM
  -n, --dry-run       report the mapping, write nothing
  -h, --help          this text

Supported: .flac (metaflac), .m4a/.mp4 (ffmpeg), .mp3 (mid3v2, in place)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
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

# Cases needing knowledge rather than string surgery; the rest fall through.
normalise_album() {
  local a="$1"
  case "$a" in
  # folds with the plain "[Silent Hill]" rip of the same 1999 game
  "Silent Hill OST")
    echo "Silent Hill"
    return
    ;;
  "Silent Hill 4 Soundtrack (Disc 1)")
    echo "Silent Hill 4: The Room"
    return
    ;;
  "Silent Hill Shattered Memories Soundtrack")
    echo "Silent Hill: Shattered Memories"
    return
    ;;
  # qualified: the game of the same name is also in rotation
  "Silent Hill Movie")
    echo "Silent Hill (film)"
    return
    ;;
  # en dash, not the hyphen the ripper wrote
  "Runaljod - Gap Var Ginnunga")
    echo "Runaljod – Gap Var Ginnunga"
    return
    ;;
  esac

  # Order matters: the disc marker has to go before the suffix is at the end.
  a="${a% (Disc [0-9]*)}"
  a="${a% Original Soundtracks}"
  a="${a% Original Soundtrack}"
  a="${a% Soundtrack}"
  a="${a% OST}"
  echo "$a"
}

# Case-insensitive: containers disagree on tag case.
read_tag() {
  local key="$2"
  ffprobe -v quiet -show_format -of default=noprint_wrappers=1 "$1" 2>/dev/null |
    awk -F= -v k="$key" 'tolower($1)=="tag:" k {print $2; exit}'
}

write_album() {
  local file="$1" value="$2" ext="$3" tmp
  case "$ext" in
  flac)
    # --no-utf8-convert: the value is already UTF-8. Without it metaflac
    # converts from the local charset and, failing to resolve a UTF-8
    # locale, substitutes '#' per byte - an en dash becomes "###", exit
    # status 0. The read-back below is what caught it.
    metaflac --no-utf8-convert \
      --remove-tag=ALBUM --set-tag="ALBUM=$value" "$file"
    ;;
  m4a | mp4)
    # Without use_metadata_tags the mov muxer silently DROPS the tag.
    # Remuxes, so this is also the path that could lose ReplayGain.
    tmp="$(dirname "$file")/.albtmp.$$.$ext"
    ffmpeg -nostdin -hide_banner -loglevel error -y -i "$file" -c copy \
      -movflags use_metadata_tags \
      -metadata "album=$value" "$tmp"
    mv "$tmp" "$file"
    ;;
  mp3)
    # In place. ffmpeg -c copy would rewrite the Xing/LAME header and
    # shift the decoded audio.
    mid3v2 -A "$value" "$file" >/dev/null
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
lostgain=0

while IFS= read -r -d '' file; do
  name="$(basename "$file")"
  ext="${name##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
  flac | m4a | mp4 | mp3) ;;
  *)
    printf '  SKIP  %-46s unsupported (.%s)\n' "${name:0:46}" "$ext"
    unsupported=$((unsupported + 1))
    continue
    ;;
  esac

  # Everything between the leading [ and the first ].
  case "$name" in
  \[*\]*)
    raw="${name#[}"
    raw="${raw%%]*}"
    ;;
  *)
    printf '  SKIP  %-46s no [bracket] prefix\n' "${name:0:46}"
    unsupported=$((unsupported + 1))
    continue
    ;;
  esac

  album="$(normalise_album "$raw")"

  if [ "$FORCE" -eq 0 ] && [ -n "$(read_tag "$file" album)" ]; then
    printf '  have  %-46s %s\n' "${name:0:46}" "$(read_tag "$file" album)"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY" -eq 1 ]; then
    printf '  dry   %-46s [%s] -> %s\n' "${name:0:46}" "$raw" "$album"
    continue
  fi

  gain_before="$(read_tag "$file" replaygain_track_gain)"

  if ! write_album "$file" "$album" "$ext"; then
    printf '  FAIL  %-46s write failed\n' "${name:0:46}"
    failed=$((failed + 1))
    continue
  fi

  # Read back. MP4 in particular will accept a write and store nothing.
  if [ "$(read_tag "$file" album)" != "$album" ]; then
    printf '  FAIL  %-46s tag did not survive write\n' "${name:0:46}"
    failed=$((failed + 1))
    continue
  fi

  # A silently dropped gain only surfaces later as one track being louder.
  if [ -n "$gain_before" ] && [ -z "$(read_tag "$file" replaygain_track_gain)" ]; then
    printf '  WARN  %-46s lost ReplayGain - rerun tag-replaygain\n' "${name:0:46}"
    lostgain=$((lostgain + 1))
  fi

  printf '  tag   %-46s %s\n' "${name:0:46}" "$album"
  tagged=$((tagged + 1))
done < <(find "$DIR" -maxdepth 1 -type f -print0 | sort -z)

echo
echo "  tagged: $tagged   already tagged: $skipped   failed: $failed   unsupported: $unsupported"
[ "$lostgain" -eq 0 ] || echo "  WARNING: $lostgain file(s) lost ReplayGain"
[ "$failed" -eq 0 ] && [ "$lostgain" -eq 0 ]
