# `transcribe-parakeet <file>`: Parakeet TDT 0.6b v3 on CPU; see
# transcribe/README.md. VAD is required: without it, long output is word salad.
{
  coreutils,
  curl,
  ffmpeg,
  gawk,
  lib,
  sherpa-onnx,
  writeShellApplication,
}: let
  repo = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main";
  sileroUrl = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx";
in
  writeShellApplication {
    name = "transcribe-parakeet";
    runtimeInputs = [coreutils curl ffmpeg gawk];
    text = ''
      set -euo pipefail
      # Store path, resolved at build time; shellcheck can't follow it.
      # shellcheck source=/dev/null
      source ${./transcribe/common.sh}

      fmt=txt
      out=.

      usage() {
        cat <<'EOF'
      transcribe-parakeet [options] <audio-or-video>

        Parakeet TDT 0.6b v3 (sherpa-onnx, CPU, language auto-detected).
        For phone/noisy/multilingual audio use transcribe (whisper) instead.

        -f, --format FMT      txt|srt|vtt|json  (default: txt)
        -o, --output DIR      default: current directory
      EOF
      }

      while [ $# -gt 0 ]; do
        case "$1" in
          -f|--format) fmt="$2"; shift 2 ;;
          -o|--output) out="$2"; shift 2 ;;
          -h|--help)   usage; exit 0 ;;
          -*)          echo "transcribe-parakeet: unknown option $1" >&2; usage >&2; exit 2 ;;
          *)           break ;;
        esac
      done

      [ $# -eq 1 ] || { usage >&2; exit 2; }
      src=$1
      [ -r "$src" ] || { echo "transcribe-parakeet: cannot read $src" >&2; exit 1; }
      mkdir -p "$out"
      base=$(basename "''${src%.*}")

      wav=$(to_wav "$src")
      trap 'rm -f "$wav"' EXIT

      store=''${XDG_DATA_HOME:-$HOME/.local/share}/asr-models
      m=$store/parakeet-tdt-0.6b-v3
      for f in encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt; do
        fetch "${repo}/$f" "$m/$f"
      done
      fetch "${sileroUrl}" "$store/silero_vad.onnx"

      ${lib.getExe' sherpa-onnx "sherpa-onnx-vad-with-offline-asr"} \
        --silero-vad-model="$store/silero_vad.onnx" \
        --encoder="$m/encoder.int8.onnx" \
        --decoder="$m/decoder.int8.onnx" \
        --joiner="$m/joiner.int8.onnx" \
        --tokens="$m/tokens.txt" \
        --model-type=nemo_transducer \
        --num-threads="$(( $(nproc) / 2 ))" \
        "$wav" 2>/dev/null \
        | gawk -v fmt="$fmt" -f ${./transcribe/segments.awk} \
        > "$out/$base.$fmt"
    '';
  }
