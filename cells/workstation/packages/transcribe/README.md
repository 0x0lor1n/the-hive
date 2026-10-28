# transcribe, transcribe-parakeet

Both take an audio or video file, convert it to 16 kHz mono with ffmpeg and
write txt/srt/vtt/json. Models are fetched on first use into
`$XDG_DATA_HOME/asr-models` (data, not cache: nothing rebuilds them on miss).

| tool | engine | where | for |
|---|---|---|---|
| `transcribe` | whisper.cpp large-v3-turbo q5_0 (518 MB) | Vulkan on the iGPU; `-C` CPU; `--ct2` faster-whisper with word timestamps | meetings, phone audio, noise; `-l` language flag |
| `transcribe-parakeet` | Parakeet TDT 0.6b v3 int8 (458 MB) via sherpa-onnx, silero VAD | CPU only | clean speech (narration, mic'd interviews) |

## Measured on elster

French, WER by word-level Levenshtein with case and punctuation folded:

|  | FLEURS, studio, 285 s | MINDS-14, phone 8 kHz, 184 s |
|---|---|---|
| whisper | 15.8 %, 57 s, Iris Xe | 27.2 %, 31 s, Iris Xe |
| parakeet | 14.4 %, 29 s, CPU 10t | 35.6 %, 19 s, CPU 10t |

Qwen3-ASR 0.6B (21.3 % / 37.2 %) and Canary 1B (slower than whisper, also
hallucinates) lost on both sets.

## Traps

- Parakeet has no language flag. On poor audio its language ID drifts and it
  emits fluent Spanish or English for French input: a plausible transcript,
  not a visible failure.
- Without VAD segmentation Parakeet's long-form output degrades into word
  salad. int8 and fp32 score the same, so only int8 is fetched.
- onnxruntime's OpenVINO EP cannot run Parakeet on the iGPU (dynamic rank in
  the TDT decoder), which also leaves the GPU free for whisper.
- A SYCL/oneAPI whisper build was dropped: fp16 aborts im2col on Gen12 and the
  flash-attn kernels spill ~287 registers; without both it was 10x slower than
  Vulkan, for a 5 GB unfree toolkit with no binary cache.
