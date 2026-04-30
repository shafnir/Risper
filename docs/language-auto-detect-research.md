# Language Auto-Detect Research

Date: 2026-04-30

## Recommendation

Do not add English/Hebrew auto-detect to the MVP using the current Ivrit.ai model. Keep Risper forced to Hebrew for now.

The current Ivrit.ai Hebrew fine-tune is a good local Hebrew model, but it is not a good language detector: the Ivrit.ai model card says language detection was degraded during training and that the language token should be explicitly set to Hebrew. The `ivrit-ai/whisper-large-v3-turbo-ggml` package is compatible with `whisper.cpp`, so it remains the right local-first Hebrew runtime for this MVP.

If English/Hebrew auto-detect becomes important, evaluate it as a separate post-MVP spike using a general multilingual Whisper model for language detection, then route Hebrew dictation to the Ivrit.ai model and English dictation to a general multilingual model. Do not switch the current Ivrit.ai server to `language=auto` without measuring quality.

## Findings

- Ivrit.ai `whisper-large-v3-turbo` is a Hebrew fine-tune of OpenAI Whisper Large v3 Turbo, trained in April 2025, with a 0.8B parameter model card. It is optimized for mostly Hebrew transcription, not reliable language identification.
- Ivrit.ai explicitly documents that language detection capability degraded during training and recommends explicitly setting Hebrew.
- Ivrit.ai `whisper-large-v3-turbo-ggml` is compatible with `whisper.cpp`, which matches Risper's local SwiftPM/AppKit plus local `whisper-server` architecture.
- Ivrit.ai also publishes CTranslate2/faster-whisper formats, but adopting those would add a Python/CTranslate2 runtime path that does not fit the current SwiftPM-first MVP.
- `whisper.cpp` supports local Mac inference and documents Apple Silicon support through ARM NEON, Accelerate, Metal, and optional Core ML. Its server accepts `--language auto` and `--detect-language`, so auto-detect is technically available with an appropriate multilingual model.
- OpenAI Whisper itself was trained for multilingual transcription and language-identification behavior, but that capability should be validated with the exact local model and short-dictation latency target before product use.

## Sources

- Ivrit.ai `whisper-large-v3-turbo` model card: https://huggingface.co/ivrit-ai/whisper-large-v3-turbo
- Ivrit.ai `whisper-large-v3-turbo-ggml` model card: https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml
- Ivrit.ai `whisper-large-v3-turbo-ct2` model card: https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2
- `whisper.cpp` README: https://github.com/ggml-org/whisper.cpp
- `whisper.cpp` server README: https://github.com/ggml-org/whisper.cpp/blob/master/examples/server/README.md
- OpenAI Whisper announcement: https://openai.com/research/whisper/
