# Risper Specs

Status: draft  
Date: 2026-04-29

## Vision

Risper is a local-first Hebrew dictation utility for macOS. The user holds a global hotkey, speaks Hebrew, releases the hotkey, and the transcript is inserted into the current cursor in whatever app is focused.

The product should feel like a minimal Wispr/Whisper Flow-style workflow, but all audio processing runs locally on the Mac. No audio leaves the machine in the MVP.

## Current Environment

- Workspace: project directory at `/Users/developer/Github/Risper`.
- Target machine: Apple Silicon (`arm64`), macOS 26.3.1.
- Installed and selected: Xcode 26.4.1 at `/Applications/Xcode.app/Contents/Developer`, Swift 6.3.1, Apple Metal compiler, Homebrew, `cmake`, and `ffmpeg`.
- Local model present: Ivrit.ai `whisper-large-v3-turbo-ggml` `ggml-model.bin` under `~/Library/Application Support/Risper/Models/ivrit-large-v3-turbo/`.
- Development implication: SwiftPM-first app bootstrap can proceed; `whisper.cpp` Metal build is now feasible in Phase 1.

## Prerequisites

Check these before implementation starts:

- Hardware: Apple Silicon Mac with enough free disk space for the app, `whisper.cpp`, build outputs, and the 1.62 GB Ivrit.ai model.
- macOS: current target is macOS 26.3.1; MVP should stay compatible with this version first.
- Developer tools: Swift toolchain and full Xcode selected; Apple Metal compiler available for `whisper.cpp` work.
- Homebrew: installed and usable from `/opt/homebrew/bin/brew`.
- Build tools: `cmake` installed before building `whisper.cpp`.
- Audio tools: `ffmpeg` installed for WAV conversion/debugging.
- Network setup window: internet access available only for initial dependency/model download; MVP runtime must work offline after setup.
- Local model: Ivrit.ai `whisper-large-v3-turbo-ggml` `ggml-model.bin` downloaded to the chosen Application Support model path.
- macOS permissions: user must be able to grant Microphone and Accessibility permissions to the app.
- Trigger availability: target UX is long-press `fn`, matching Wispr Flow-style push-to-talk on built-in Mac keyboards. During early development, `Control+Option+Space` is the simple working trigger so recording, ASR, and paste can be built before low-level input monitoring.
- Target apps for MVP QA: TextEdit or Notes, Chrome text fields, Cursor, and Slack installed or otherwise replaceable with agreed equivalents.
- Org rollout prerequisites, post-MVP only: MDM access or Apple Developer Program decision for distribution.

## Product Decisions

- Build a minimal local macOS app/agent from the start. Do not start with web app, Hammerspoon, Keyboard Maestro, Docker, or Apple Silicon containers.
- Keep the UI tiny: status/menu bar presence, permissions state, and basic diagnostics only.
- Use SwiftPM as the first project shape. Follow the Build macOS Apps plugin guidance: provide one project-local `script/build_and_run.sh` entrypoint that builds, stages a `.app` bundle, launches it, and supports verification/log modes later.
- Use AppKit where macOS requires imperative behavior: status item, app lifecycle, global hotkey, Accessibility permission checks, pasteboard injection, and process management.
- Use SwiftUI only if a settings window becomes necessary after MVP.
- Use `whisper.cpp` locally for ASR because it is Apple Silicon optimized with Metal/Core ML support.
- Use the Ivrit.ai `whisper-large-v3-turbo-ggml` model, file `ggml-model.bin`, stored under `~/Library/Application Support/Risper/Models/ivrit-large-v3-turbo/`.
- Force Hebrew transcription: language `he`, task `transcribe`, no translation, no language auto-detection.
- Keep the model warm by running a local `whisper-server` process bound to `127.0.0.1`; do not shell out to a fresh `whisper-cli` process for each dictation except as a debug fallback.
- Use pasteboard + synthetic Cmd+V for MVP text insertion, while preserving and restoring the user's clipboard.
- Use `Control+Option+Space` first through the standard global hotkey path. Add bare `fn` long-press after the core dictation loop works, because it requires low-level event monitoring and a stable permission/signing story.
- Do not require an Apple paid developer account for MVP. Signing/notarization is a post-MVP distribution concern unless org policy requires it sooner.

## Technical Stack

- App: Swift, SwiftPM, AppKit-first minimal menu bar/background app.
- Audio capture: `AVAudioEngine`, 16 kHz mono PCM WAV output for transcription.
- ASR runtime: pinned `whisper.cpp` release, built locally with Metal enabled.
- ASR API: local HTTP server on `127.0.0.1:8178`, preferably using an OpenAI-compatible `/v1/audio/transcriptions` endpoint if available; otherwise use `whisper-server` `/inference` with JSON response.
- Model: Ivrit.ai `whisper-large-v3-turbo-ggml` `ggml-model.bin` (1.62 GB).
- Config: `~/Library/Application Support/Risper/config.json`.
- Temp audio: `~/Library/Caches/Risper/recordings/`, deleted after successful or failed transcription unless debug mode is enabled.
- Logs: macOS unified logging plus local event logs without transcript text by default.

## MVP UX

- First launch shows only the minimum needed state: app is running, model present/missing, microphone permission, trigger state, and ASR server state. Accessibility is only required later for paste insertion and `fn` monitoring.
- Target trigger: long-press `fn`; development trigger until the dictation loop works: `Control+Option+Space`.
- Dictation loop:
  1. User presses and holds the active trigger.
  2. App starts recording and gives a minimal visible or audible state change.
  3. User releases the hotkey.
  4. App stops recording, sends audio to local ASR, receives Hebrew text, trims obvious whitespace/timestamps, and pastes at the current cursor.
  5. Clipboard is restored after paste.
- Error behavior:
  - Missing model: app menu shows setup-needed state and no recording starts.
  - Microphone denied: app explains that recording cannot start.
  - Accessibility denied: app can transcribe but cannot inject.
  - ASR failure: clipboard remains untouched/restored and the user receives a concise failure state.
  - Paste failure: transcript remains available in memory via "Copy Last Transcript" until the app quits.
- MVP intentionally excludes transcript editor UI, command mode, custom vocabulary, model switching, cloud fallback, auto-updater, and org deployment packaging.

## Phases

### Phase 0: Planning And Repo Bootstrap

- Create `specs.md` and `tasks.md`.
- Initialize the repo only when implementation starts.
- Add `.gitignore` for build outputs, model files, temp audio, and local diagnostics.
- Add SwiftPM package structure and a project-local build/run script.

### Phase 1: Local ASR Harness

- Install/verify local prerequisites: Homebrew, Swift toolchain, `cmake`, `ffmpeg`.
- Build pinned `whisper.cpp` locally with Metal support.
- Download the Ivrit.ai `ggml-model.bin` into Application Support.
- Run `whisper-server` locally on `127.0.0.1:8178`.
- Verify Hebrew transcription from a known WAV sample through HTTP.

### Phase 2: Minimal macOS App

- Create the minimal SwiftPM macOS app bundle.
- Add status/menu bar lifecycle.
- Add microphone permission flow and `AVAudioEngine` recording.
- Add global hotkey handling with `Control+Option+Space`.
- Add low-level event-tap handling for long-press `fn` after the basic dictation loop works.
- Add local ASR server manager and transcription client.
- Add Accessibility permission check.
- Add pasteboard-preserving text injection into the focused app.
- Add minimal diagnostics: server status, model path, last error, copy last transcript.

### Phase 3: MVP Hardening

- Keep ASR server warm and restart it if it exits unexpectedly.
- Delete temp audio by default.
- Ensure clipboard is restored on success and failure.
- Add deterministic debug logs that do not include transcript content unless debug mode is explicitly enabled.
- Add manual QA checklist and focused automated tests for pure logic.
- Validate the full dictation loop across agreed target apps.

### Phase 4: Internal Pilot Readiness

- Package an internal build that can be installed without source checkout.
- Decide whether rollout uses MDM, ad-hoc signing, or Apple Developer ID signing.
- Add PPPC/MDM notes for Accessibility and Microphone permissions if org deployment is selected.
- Add basic crash/log collection instructions that preserve privacy.
- Add onboarding docs for internal users.

### Phase 5: Post-MVP Productization

- Add settings UI for hotkey, model path, diagnostics, and startup behavior.
- Add alternate insertion fallback using direct Unicode key events for apps where paste is unreliable.
- Add optional model management: download, verify checksum, update, rollback.
- Add better Hebrew text cleanup and optional prompt/context tuning.
- Add real-time/streaming transcription only if MVP latency is not acceptable.
- Add signed/notarized distribution only when non-MDM distribution or lower-friction org rollout requires it.

## MVP Quality Gates

MVP is ready for real usage testing only when all gates pass on the target Mac:

- Build gate: `script/build_and_run.sh --verify` builds, stages, launches, and confirms the app process.
- Locality gate: dictation works with network disabled after model/dependency setup.
- ASR gate: a known Hebrew WAV sample transcribes through local `whisper-server` with usable Hebrew text.
- Permission gate: microphone and Accessibility denied/granted states are detected and reported correctly.
- Hotkey gate: the development shortcut starts/stops recording first. Before MVP user testing, long-press `fn` should provide the same press/release behavior on built-in Mac keyboards, with `Control+Option+Space` kept as fallback.
- Injection gate: Hebrew text is inserted at the current cursor in TextEdit/Notes, Chrome text fields, Cursor, and Slack.
- Clipboard gate: existing clipboard contents are restored after successful paste, failed ASR, and paste failure.
- Failure gate: missing model, ASR server crash, empty audio, no focused text field, and denied permissions fail without app crash or clipboard loss.
- Privacy gate: temp audio is deleted by default and logs do not contain transcript text unless debug mode is enabled.
- Performance gate: after the model is warm, normal short dictations feel suitable for interactive use on the target Mac.

## Continue Past MVP When

- All MVP quality gates pass.
- Real usage testing produces no P0/P1 issues in the target apps.
- Remaining issues are either app-specific compatibility gaps or product polish.
- The next phase has one clear goal: internal pilot packaging, text-insertion reliability, UX/settings polish, or ASR quality improvements.

## References

- Build macOS Apps plugin guidance used: SwiftPM-first workflow, AppKit interop, build/run script, signing/notarization separation.
- `whisper.cpp`: https://github.com/ggml-org/whisper.cpp
- Ivrit.ai ggml model: https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/tree/main
- Apple microphone privacy key: https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription
- Apple Accessibility trust API: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- Apple pasteboard API: https://developer.apple.com/documentation/appkit/nspasteboard
