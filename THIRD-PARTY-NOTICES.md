# Third-Party Notices

Risper bundles and depends on the following third-party components. Each is the
property of its respective authors and is used under its own license.

## whisper.cpp

- Project: https://github.com/ggml-org/whisper.cpp
- License: MIT (Copyright (c) 2023-2026 The ggml authors)
- Usage: `whisper-server` and the `whisper`/`ggml` dynamic libraries provide the
  local speech-recognition runtime. They are built from source during
  development and bundled into the offline DMG. The source is not vendored in
  this repository; it is cloned at build time (see the README).

## Ivrit.ai Hebrew Whisper model

- Model: `ivrit-ai/whisper-large-v3-turbo-ggml`
- Source: https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml
- License: Apache-2.0
- Usage: the `ggml-model.bin` weights provide local Hebrew transcription. The
  model is downloaded at setup time and is bundled into the offline DMG.

The model card lists the license as Apache-2.0, which permits redistribution of
the weights (including bundling `ggml-model.bin` inside a downloadable app),
provided the Apache-2.0 license text and attribution travel with the
distribution. This notice provides that attribution. A full copy of the
Apache-2.0 license is available at https://www.apache.org/licenses/LICENSE-2.0.

## OpenAI Whisper

The Ivrit.ai model is a fine-tune of OpenAI's Whisper large-v3. OpenAI's Whisper
models and code are released under the MIT License
(https://github.com/openai/whisper).
