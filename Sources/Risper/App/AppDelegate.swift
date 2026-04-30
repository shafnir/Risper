import AppKit
import ApplicationServices
import AVFoundation
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, TriggerMonitorDelegate, StatusMenuControllerDelegate {
    private lazy var statusController = StatusMenuController(delegate: self)
    private lazy var fallbackHotKeyMonitor = FallbackHotKeyMonitor(delegate: self)
    private let audioRecorder = AudioRecorder()
    private let asrClient = ASRClient()
    private let textInjector = TextInjector()

    private var activeTrigger: TriggerSource?
    private var lastTriggerDescription = "None"
    private var dictationStatus = "Idle"
    private var isDictationBusy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusController.refresh(
            accessibilityStatus: AccessibilityPermission.statusDescription,
            microphoneStatus: MicrophonePermission.statusDescription,
            modelStatus: ModelLocator.statusDescription,
            asrServerStatus: ASRServerStatus.description,
            functionKeyStatus: FunctionKeyLongPressMonitor.simpleModeStatus,
            fallbackStatus: "Starting",
            recordingStatus: audioRecorder.statusDescription,
            dictationStatus: dictationStatus,
            lastRecording: audioRecorder.lastRecordingDescription,
            activeTrigger: activeTriggerDescription,
            lastTrigger: lastTriggerDescription
        )

        fallbackHotKeyMonitor.start()
        refreshStatusMenu()
        RisperLog.app.info("Risper app shell started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = audioRecorder.stopRecording()
        fallbackHotKeyMonitor.stop()
    }

    func triggerDidBegin(source: TriggerSource) {
        guard activeTrigger == nil else { return }
        guard !isDictationBusy else {
            lastTriggerDescription = "\(source.rawValue) ignored; dictation in progress"
            refreshStatusMenu()
            return
        }

        activeTrigger = source
        lastTriggerDescription = "\(source.rawValue) began"
        RisperLog.app.info("Trigger began: \(source.rawValue, privacy: .public)")

        do {
            try audioRecorder.startRecording()
        } catch {
            activeTrigger = nil
            lastTriggerDescription = "\(source.rawValue) began; recording unavailable"
            RisperLog.app.error("Recording did not start: \(error.localizedDescription, privacy: .public)")
        }

        refreshStatusMenu()
    }

    func triggerDidEnd(source: TriggerSource) {
        guard activeTrigger == source else { return }
        activeTrigger = nil

        if let recording = audioRecorder.stopRecording() {
            transcribeAndPaste(recording: recording, source: source)
        } else {
            lastTriggerDescription = "\(source.rawValue) ended"
            refreshStatusMenu()
        }

        RisperLog.app.info("Trigger ended: \(source.rawValue, privacy: .public)")
    }

    func triggerMonitorStatusDidChange() {
        refreshStatusMenu()
    }

    func refreshStatusMenu() {
        statusController.refresh(
            accessibilityStatus: AccessibilityPermission.statusDescription,
            microphoneStatus: MicrophonePermission.statusDescription,
            modelStatus: ModelLocator.statusDescription,
            asrServerStatus: ASRServerStatus.description,
            functionKeyStatus: FunctionKeyLongPressMonitor.simpleModeStatus,
            fallbackStatus: fallbackHotKeyMonitor.statusDescription,
            recordingStatus: audioRecorder.statusDescription,
            dictationStatus: dictationStatus,
            lastRecording: audioRecorder.lastRecordingDescription,
            activeTrigger: activeTriggerDescription,
            lastTrigger: lastTriggerDescription
        )
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshStatusMenu()
            }
        }
    }

    func openPrivacySettings() {
        AccessibilityPermission.requestIfNeeded()

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var activeTriggerDescription: String {
        activeTrigger?.rawValue ?? "Idle"
    }

    private func transcribeAndPaste(recording: RecordingResult, source: TriggerSource) {
        isDictationBusy = true
        dictationStatus = "Transcribing"
        lastTriggerDescription = "\(source.rawValue) ended; transcribing \(recording.url.lastPathComponent)"
        refreshStatusMenu()

        asrClient.transcribe(recording: recording) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleTranscriptionResult(result, source: source)
            }
        }
    }

    private func handleTranscriptionResult(_ result: Result<String, Error>, source: TriggerSource) {
        switch result {
        case .success(let transcript):
            RisperLog.app.info("Transcription completed: \(transcript.count, privacy: .public) characters")
            paste(transcript, source: source)
        case .failure(let error):
            dictationStatus = dictationFailureStatus(for: error)
            lastTriggerDescription = "\(source.rawValue) ended; transcription failed"
            RisperLog.app.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        }

        isDictationBusy = false
        refreshStatusMenu()
    }

    private func paste(_ transcript: String, source: TriggerSource) {
        dictationStatus = "Pasting"
        refreshStatusMenu()

        do {
            try textInjector.paste(transcript)
            dictationStatus = "Inserted"
            lastTriggerDescription = "\(source.rawValue) ended; inserted transcript"
            RisperLog.app.info("Transcript inserted")
        } catch {
            if case TextInjectorError.accessibilityRequired = error {
                dictationStatus = "Transcribed; Accessibility required"
            } else {
                dictationStatus = "Paste failed"
            }

            lastTriggerDescription = "\(source.rawValue) ended; paste failed"
            RisperLog.app.error("Paste failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func dictationFailureStatus(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
                return "ASR unavailable"
            default:
                return "ASR failed"
            }
        }

        if case ASRClientError.emptyTranscript = error {
            return "Empty transcript"
        }

        return "ASR failed"
    }
}
