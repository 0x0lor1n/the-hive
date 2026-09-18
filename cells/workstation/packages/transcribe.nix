# `transcribe <file>`: ffmpeg to 16 kHz mono, then whisper.cpp.
#
# The Parakeet engine lives in transcribe-parakeet.nix: its flags don't overlap
# with this one's (no -m ggml file, no -l -- Parakeet only auto-detects), and
# that file carries the WER measurements that decide which to reach for.
#
# --ct2 is faster-whisper (CTranslate2), CPU, and the one that gives word
# timestamps.
#
# A SYCL/oneAPI build was tried first and dropped: fp16 aborts im2col on Gen12
# and the flash-attn kernels spill ~287 registers, so both had to go, leaving
# it 10x slower than Vulkan for a 5 GB unfree toolkit that has no binary cache.
#
# Models are fetched on first use into $XDG_DATA_HOME/asr-models (518 MB for
# large-v3-turbo q5_0). Data, not cache: nothing rebuilds them on miss, so they
# live where a `rm -rf ~/.cache` cannot take them offline.
{
  coreutils,
  curl,
  ffmpeg,
  lib,
  whisper-cpp,
  whisper-cpp-vulkan,
  whisper-ctranslate2,
  writeShellApplication,
}: let
  repo = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main";
in
  writeShellApplication {
    name = "transcribe";
    runtimeInputs = [coreutils curl ffmpeg];
    text = ''
      set -euo pipefail
      # Store path, resolved at build time; shellcheck can't follow it.
      # shellcheck source=/dev/null
      source ${./transcribe/common.sh}

      model=large-v3-turbo-q5_0
      lang=fr
      backend=gpu
      fmt=txt
      out=.

      usage() {
        cat <<'EOF'
      transcribe [options] <audio-or-video>

        whisper.cpp large-v3-turbo. For clean speech see transcribe-parakeet:
        ~2x faster and slightly more accurate, but no language flag.

        (default)             Vulkan on the Intel iGPU
        -C, --cpu             CPU backend
        -c, --ct2             faster-whisper/CTranslate2 (word timestamps)
        -m, --model NAME      default: large-v3-turbo-q5_0
        -l, --lang CODE       default: fr; "auto" to detect
        -f, --format FMT      txt|srt|vtt|json  (default: txt)
        -o, --output DIR      default: current directory
      EOF
      }

      while [ $# -gt 0 ]; do
        case "$1" in
          -C|--cpu)    backend=cpu; shift ;;
          -g|--gpu)    backend=gpu; shift ;;
          -c|--ct2)    backend=ct2; shift ;;
          -m|--model)  model="$2"; shift 2 ;;
          -l|--lang)   lang="$2"; shift 2 ;;
          -f|--format) fmt="$2"; shift 2 ;;
          -o|--output) out="$2"; shift 2 ;;
          -h|--help)   usage; exit 0 ;;
          -*)          echo "transcribe: unknown option $1" >&2; usage >&2; exit 2 ;;
          *)           break ;;
        esac
      done

      [ $# -eq 1 ] || { usage >&2; exit 2; }
      src=$1
      [ -r "$src" ] || { echo "transcribe: cannot read $src" >&2; exit 1; }
      mkdir -p "$out"
      base=$(basename "''${src%.*}")

      if [ "$backend" = ct2 ]; then
        exec ${lib.getExe whisper-ctranslate2} "$src" \
          --model "$model" --language "$lang" --device cpu \
          --output_dir "$out" --output_format "$fmt"
      fi

      wav=$(to_wav "$src")
      trap 'rm -f "$wav"' EXIT

      store=''${XDG_DATA_HOME:-$HOME/.local/share}/asr-models
      gguf="$store/ggml-$model.bin"
      fetch "${repo}/ggml-$model.bin" "$gguf"

      case "$backend" in
        gpu) cli=${lib.getExe' whisper-cpp-vulkan "whisper-cli"} ;;
        *)   cli=${lib.getExe' whisper-cpp "whisper-cli"} ;;
      esac

      flag=--output-txt
      case "$fmt" in
        srt)  flag=--output-srt ;;
        vtt)  flag=--output-vtt ;;
        json) flag=--output-json ;;
      esac

      "$cli" -m "$gguf" -l "$lang" -f "$wav" "$flag" -of "$out/$base"
    '';
  }
