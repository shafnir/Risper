# Debugging macOS Permissions And Input

Use this playbook before changing runtime behavior for microphone, Accessibility,
global hotkeys, app overlays, clipboard, or cross-app paste regressions.

## First Principle

If the last commit worked, preserve the last-known-good runtime path until there
is direct evidence it is the cause. Packaging, signing, bundle metadata, install
location, and TCC state can break macOS permissions without requiring Swift
runtime changes.

## Baseline Checks

Compare runtime source against the last commit:

```bash
git diff HEAD -- Sources/Risper
```

Check which app is actually running:

```bash
pgrep -fl 'Risper|whisper-server'
```

Inspect the installed bundle metadata:

```bash
/usr/bin/plutil -p /Applications/Risper.app/Contents/Info.plist | rg 'CFBundleIdentifier|NSMicrophone|NSInputMonitoring'
codesign -d -r- /Applications/Risper.app
```

Read recent privacy and app lifecycle logs:

```bash
/usr/bin/log show --last 15m --info --debug --style compact --predicate 'subsystem == "com.risper.Risper"'
```

## Verification Checklist

For permission, hotkey, overlay, or paste changes, do not stop at build success
or log success. Verify the actual workflow:

1. Launch `/Applications/Risper.app`.
2. Focus a text field in TextEdit or another target app.
3. Hold `fn` until the recording indicator appears.
4. Speak a short phrase.
5. Release `fn`.
6. Wait for transcription.
7. Confirm text appears at the original cursor.
8. Confirm the clipboard is restored.

If manual verification cannot be completed from the agent environment, say so
explicitly and document the exact remaining check.

## Triage Order

1. Confirm the running app path is the intended bundle.
2. Confirm bundle id and permission usage strings are present.
3. Confirm signing identity/designated requirement is stable.
4. Confirm logs show the expected existing monitor implementation.
5. Confirm microphone recording starts and stops.
6. Confirm ASR returns a non-empty transcript.
7. Confirm paste succeeds in the focused app.
8. Only then consider changing runtime input, recording, or paste code.

## TCC Reset

Do not reset privacy permissions unless the user approves it. Prefer a
bundle-specific reset when available:

```bash
tccutil reset Accessibility com.risper.Risper
```

After any reset, relaunch the app and re-grant permissions in System Settings.
