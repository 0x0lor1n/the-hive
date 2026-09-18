# Sourced by transcribe and transcribe-parakeet: the two things both engines
# need, kept in one place so the download semantics can't drift apart.

# Resume-capable, and a truncated download never lands on the final name.
fetch() {
  local url=$1 dest=$2
  [ -e "$dest" ] && return 0
  echo "${0##*/}: fetching $(basename "$dest")" >&2
  mkdir -p "$(dirname "$dest")"
  curl -fL --progress-bar -C - -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

# whisper.cpp and sherpa-onnx both only read 16 kHz mono PCM. Prints the path of
# a temp copy; the caller owns removing it.
to_wav() {
  local wav
  wav=$(mktemp --suffix=.wav)
  ffmpeg -loglevel error -y -i "$1" -ar 16000 -ac 1 -c:a pcm_s16le "$wav"
  printf '%s\n' "$wav"
}
