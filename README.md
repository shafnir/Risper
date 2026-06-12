# Risper

**Local-first Hebrew dictation for macOS.**

Risper is a tiny menu bar app: hold a key, speak Hebrew, release, and the
transcript is inserted into whatever app you were already typing in. Speech
recognition runs entirely on your Mac with `whisper.cpp` — there is **no cloud
ASR and no transcript upload**.

![Risper local Hebrew dictation hero](docs/assets/risper-readme-hero.png)

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B%20·%20Apple%20Silicon-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Latest release](https://img.shields.io/github/v/release/shafnir/Risper)

### ⬇️ [Download the latest Risper for macOS (Apple Silicon)](https://github.com/shafnir/Risper/releases/latest/download/Risper-offline-arm64.dmg)

This link always points to the newest release. Browse
[all releases](https://github.com/shafnir/Risper/releases) for notes.

---

## Contents

- [For Users](#for-users) — install and use the app (no developer tools)
  - [Requirements](#requirements)
  - [Install](#install)
    - [Quick install (recommended)](#quick-install-recommended)
    - [Manual install (DMG)](#manual-install-dmg)
  - [Using Risper](#using-risper)
  - [Troubleshooting](#troubleshooting)
- [For Developers](#for-developers) — build, package, and contribute
  - [Developer requirements](#developer-requirements)
  - [Build and run from source](#build-and-run-from-source)
  - [Set up the local ASR runtime](#set-up-the-local-asr-runtime)
  - [Package the offline DMG](#package-the-offline-dmg)
  - [Verify transcription](#verify-transcription)
  - [Logs and debugging](#logs-and-debugging)
  - [Project layout](#project-layout)
- [How It Works](#how-it-works)
- [Privacy](#privacy)
- [Scope](#scope)
- [License](#license)

---

# For Users

You do **not** need Xcode, Homebrew, the source code, or any model download. The
DMG is self-contained.

## Requirements

- Apple Silicon Mac (arm64).
- macOS 26 or newer.
- Permission to grant **Microphone** and **Accessibility** access in System
  Settings.

## Install

### Quick install (recommended)

Paste this into **Terminal** and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/shafnir/Risper/main/script/install.sh | bash
```

It downloads the latest release, installs **Risper.app** into `/Applications`,
and launches it. You may be asked for your Mac password (to write to
`/Applications`). **No "could not verify Risper" warning appears** with this
method — see [Why the Terminal install skips the warning](#why-the-terminal-install-skips-the-warning).

Then finish the two permission steps:

1. Grant **Microphone** permission when prompted.
2. Grant **Accessibility** permission in
   **System Settings → Privacy & Security → Accessibility**, enable Risper, then
   **quit and relaunch Risper** so macOS applies the new trust.

### Manual install (DMG)

Prefer to download by hand?

1. [**Download `Risper-offline-arm64.dmg`**](https://github.com/shafnir/Risper/releases/latest/download/Risper-offline-arm64.dmg)
   and open it.
2. Drag **Risper.app** into **Applications**.
3. Launch `/Applications/Risper.app`.
4. **Expect a "could not verify Risper" warning on first launch — this is
   normal** with the manual download. See
   [Get past the first-launch warning](#get-past-the-first-launch-warning), then
   continue.
5. Grant **Microphone** and **Accessibility** permissions as above, then quit
   and relaunch Risper.

### Get past the first-launch warning

> This only happens with the **manual DMG** download. The
> [Quick install](#quick-install-recommended) above avoids it entirely.

The first time you open a browser-downloaded Risper, macOS shows a dialog titled
**"Risper" Not Opened** that says *"Apple could not verify 'Risper' is free of
malware…"*. **This is expected and Risper is safe** — speech recognition runs
entirely on your Mac with no network calls (see [Privacy](#privacy)). The
warning appears only because the app is not yet notarized by Apple, not because
anything is wrong with it.

> ⚠️ **Do not click "Move to Trash."** That deletes the app. The dialog has no
> "Open" button by design — you approve it in System Settings instead.

To open it:

1. In the warning dialog, click **Done**.
2. Open **System Settings → Privacy & Security** and scroll down to the message
   *"Risper" was blocked to protect your Mac.*
3. Click **Open Anyway**, then confirm with your password or Touch ID.
4. Launch Risper again — it now opens normally, and you won't be asked again.

**Faster alternative (Terminal):** clear the download flag in one command, then
just open the app:

```bash
xattr -dr com.apple.quarantine /Applications/Risper.app
```

### Why the Terminal install skips the warning

The DMG bundles `Risper.app`, the `whisper-server` runtime, the `whisper.cpp`
libraries, and the Ivrit.ai Hebrew model. It is locally signed but **not**
Developer ID-signed or notarized by Apple.

macOS only shows the Gatekeeper warning for apps carrying a **quarantine flag**,
which is attached to anything downloaded through a **web browser**. The Quick
install uses `curl`, which does **not** set that flag, so Gatekeeper never
blocks the app. The manual DMG path is browser-downloaded, so it gets the flag
and the one-time approval above is expected — until a notarized build is
published.

## Using Risper

> **Risper has no window.** When you double-click the app, nothing opens on
> screen — instead a **microphone icon appears in the macOS menu bar** (the
> status bar at the top right of your screen). That icon *is* the app. If you
> don't see it, it may be hidden behind other menu bar items when you have many
> apps running — widen the menu bar or use a menu bar manager to reveal it.
> Click the microphone icon to see status and options.

1. Launch Risper and confirm the menu bar item reports the model and ASR server
   as ready.
2. Focus a text field in any app.
3. Hold **`fn`** until the recording overlay appears.
4. Speak Hebrew.
5. Release **`fn`**.
6. Wait for the transcript to be inserted at your cursor.

If `fn` monitoring is unavailable, use the fallback shortcut:

```text
Control + Option + Space
```

The menu bar item also gives you:

- **Copy Last Transcript**
- **Restart ASR Server**
- **Recheck Status**
- **Request Microphone Permission** / **Open Privacy Settings**
- Current model, permission, trigger, recording, and ASR state

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| **Double-clicked the app and nothing happened** | Expected — Risper has no window. Look for the **microphone icon in the menu bar** (top-right of the screen). If it's not visible, it may be hidden behind other menu bar items — see [Using Risper](#using-risper). |
| **"Risper" Not Opened** / *"Apple could not verify… free of malware"* | Expected — see [Get past the first-launch warning](#get-past-the-first-launch-warning). Click **Done** (not "Move to Trash"), then **System Settings → Privacy & Security → Open Anyway**. |
| Menu shows **`Model: Missing`** | The bundled model didn't load. Reinstall from the latest DMG. |
| Menu shows **`ASR: Missing whisper-server`** | Reinstall from the latest DMG. |
| **`fn Long-Press`** says Accessibility is required | Grant Accessibility to `/Applications/Risper.app`, then quit and relaunch. If it's already listed but still asks, remove Risper from the list, add `/Applications/Risper.app` again, and relaunch. |
| Dictation records but no text appears | Check Accessibility permission, and try a simple target like **TextEdit** first. |

For permission-specific debugging, see
[`docs/debugging-macos-permissions.md`](docs/debugging-macos-permissions.md).

---

# For Developers

This section is for building Risper from source or producing a new DMG.

## Developer requirements

- Apple Silicon Mac, macOS 26 or newer (the Swift package targets macOS 26.0).
- Full Xcode or the Swift toolchain available from the command line.
- Homebrew, for `cmake`, `ffmpeg`, and `jq`:
  ```bash
  brew install cmake ffmpeg jq
  ```
- A local `whisper.cpp` build with `whisper-server` (see below).
- The Ivrit.ai `whisper-large-v3-turbo-ggml` model file (see below).

`lsof`, `say`, `codesign`, and `security` ship with macOS.

## Build and run from source

```bash
# Build the Swift package
swift build

# (Recommended) create a stable local code-signing identity so macOS keeps
# Accessibility trust across rebuilds
script/setup_local_codesign.sh

# Build, stage, sign, and launch the app bundle (written to dist/Risper.app)
script/build_and_run.sh

# Build and verify the app launches
script/build_and_run.sh --verify
```

## Set up the local ASR runtime

> Only needed for source builds and packaging. The downloadable DMG already
> includes the runtime and model.

Risper looks for `whisper-server` in the bundled app resources, in
`third_party/whisper.cpp/build/bin/whisper-server`, or in the path given by the
`RISPER_WHISPER_SERVER` environment variable.

Build `whisper.cpp` with Metal:

```bash
mkdir -p third_party
git clone https://github.com/ggml-org/whisper.cpp.git third_party/whisper.cpp
cmake -S third_party/whisper.cpp -B third_party/whisper.cpp/build -DGGML_METAL=ON
cmake --build third_party/whisper.cpp/build --config Release -j
```

Download the Hebrew model to the default Application Support path:

```bash
mkdir -p "$HOME/Library/Application Support/Risper/Models/ivrit-large-v3-turbo"
curl -L \
  -o "$HOME/Library/Application Support/Risper/Models/ivrit-large-v3-turbo/ggml-model.bin" \
  "https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin"
```

The model is large, so the first download takes a while. After setup, dictation
runs locally and works offline.

## Package the offline DMG

```bash
# Create a stable local code-signing identity first (recommended)
script/setup_local_codesign.sh

# Build the release app, bundle the ASR runtime + model, sign, and create the DMG
script/package_internal.sh
```

Output:

```text
dist/Risper-offline-arm64.dmg
```

The packaging machine needs the local `whisper.cpp` build and the Ivrit.ai model
present. Machines that install from the DMG do not.

## Verify transcription

Generate a short Hebrew audio fixture, start or reuse the local server, post the
WAV to `/inference`, and validate the transcript:

```bash
script/asr_harness.sh
```

Useful environment overrides:

```bash
RISPER_ASR_PORT=8178
RISPER_MODEL_PATH="$HOME/Library/Application Support/Risper/Models/ivrit-large-v3-turbo/ggml-model.bin"
RISPER_WHISPER_SERVER="$PWD/third_party/whisper.cpp/build/bin/whisper-server"
RISPER_KEEP_SERVER=1
```

## Logs and debugging

```bash
# Runtime logs from the installed app
/usr/bin/log stream --info --style compact --predicate 'subsystem == "com.risper.Risper"'

# Source-built development logs
script/build_and_run.sh --telemetry
```

For permissions, signing, TCC, hotkeys, microphone, clipboard, or cross-app
paste issues, read
[`docs/debugging-macos-permissions.md`](docs/debugging-macos-permissions.md)
first. See [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) for contribution
conventions and [`specs.md`](specs.md) for the product and architecture source
of truth.

## Project layout

```text
Sources/Risper/App             menu bar lifecycle and recording overlay
Sources/Risper/Recording       AVFoundation audio capture and WAV output
Sources/Risper/Transcription   local ASR server management and client
Sources/Risper/Triggers        fn long-press and fallback hotkey monitors
Sources/Risper/Injection       pasteboard-preserving text insertion
Sources/Risper/Permissions     Microphone and Accessibility status helpers
script/                        build, launch, packaging, and ASR harness scripts
docs/                          debugging and product notes
Resources/                     app icon resources
```

---

# How It Works

- Records only while you hold the dictation trigger.
- Converts microphone input to a local 16 kHz mono WAV.
- Sends the audio to a local `whisper.cpp` server on `127.0.0.1:8178`.
- Forces Hebrew transcription (no language auto-detection, no translation).
- Inserts the cleaned transcript into the focused app via a temporary paste.
- Restores your clipboard afterward whenever the pasteboard is unchanged.

Risper needs two macOS permissions:

- **Microphone** — to record dictation audio.
- **Accessibility** — for the `fn` long-press monitor and synthetic `Cmd+V`
  insertion into the focused app.

# Privacy

- Runtime ASR is **local-only**; the app talks to `whisper-server` over
  `127.0.0.1`.
- Audio recordings are temporary, kept under
  `~/Library/Caches/Risper/recordings/`, and deleted after transcription.
- Transcript text is not logged by default.
- The clipboard is used only momentarily for insertion and restored afterward
  when Risper still owns the temporary pasteboard contents.

There is no cloud transcription, telemetry, or transcript upload.

# Scope

The current release intentionally stays narrow:

- Hebrew dictation only.
- Local `whisper.cpp` only.
- Menu bar status UI only.
- No transcript editor, no cloud fallback, no auto-updater.
- Offline DMG only; no notarized installer yet.

See [`specs.md`](specs.md) for the full product and architecture reference.

# License

Risper is released under the [MIT License](LICENSE).

It bundles third-party components — the `whisper.cpp` runtime (MIT) and the
Ivrit.ai Hebrew model (Apache-2.0). Both permit redistribution, including
bundling the model weights in the offline DMG. See
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) for attribution details.
