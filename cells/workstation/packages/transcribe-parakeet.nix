# `transcribe-parakeet <file>`: ffmpeg to 16 kHz mono, then Parakeet TDT 0.6b v3
# through sherpa-onnx. The whisper engine is a separate tool, `transcribe`.
#
# Measured on elster over two French sets with reference text (WER by word-level
# Levenshtein, case and punctuation folded):
#
#              FLEURS, clean studio 285s   MINDS-14, phone 8 kHz 184s
#   whisper      15.8%  57s  Iris Xe        27.2%  31s  Iris Xe
#   parakeet     14.4%  29s  CPU 10t        35.6%  19s  CPU 10t
#
# So: this for clean speech (narration, mic'd interviews), whisper for meetings,
# phone audio and noise. Parakeet has no language flag and on poor audio its
# language ID drifts -- it then emits fluent Spanish or English for French
# input, which reads as a plausible transcript rather than as a failure.
# Qwen3-ASR 0.6B (21.3% / 37.2%) and Canary 1B (slower than whisper, also
# hallucinates) lost on both sets.
#
# VAD is mandatory, not a refinement: without segmentation Parakeet's long-form
# output degrades into word salad. int8 and fp32 weights both score 14.4%, so
# only int8 (458 MB) is fetched. onnxruntime's OpenVINO EP cannot run this model
# on the iGPU (dynamic rank in the TDT decoder), so this is CPU-only -- which
# also leaves the GPU free for whisper.
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
