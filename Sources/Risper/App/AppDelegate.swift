import AppKit
import ApplicationServices
import AVFoundation
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, TriggerMonitorDelegate, StatusMenuControllerDelegate {
    private lazy var statusController = StatusMenuController(delegate: self)
    private lazy var fallbackHotKeyMonitor = FallbackHotKeyMonitor(delegate: self)
    private lazy var functionKeyMonitor = FunctionKeyLongPressMonitor(delegate: self)

    private let audioRecorder = AudioRecorder()
    private let asrClient = ASRClient()
    private let asrServerManager = ASRServerManager()
    private let textInjector = TextInjector()
    private let recordingOverlay = RecordingOverlayController()
    private let languageStore = DictationLanguageStore()

    private var recordingRefreshTimer: Timer?
    private var activeTrigger: TriggerSource?
    private var lastTriggerDescription = "None"
    private var dictationStatus = "Idle"
    private var isDictationBusy = false
    private var lastTranscript: String?
    private var pendingTranscriptionRecordings: [URL: RecordingResult] = [:]
    private let minimumTranscriptionDuration: TimeInterval = 0.85
    private let minimumSpeechPeakLevel: Float = 0.20
    private let minimumSpeechAverageLevel: Float = 0.08

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        asrServerManager.onStatusChange = { [weak self] in
            self?.refreshStatusMenu()
        }
        audioRecorder.onLevelChange = { [weak self] level in
            self?.recordingOverlay.updateAudioLevel(level)
        }

        refreshStatusMenu()
        asrServerManager.start()
        fallbackHotKeyMonitor.start()
        functionKeyMonitor.start()
        refreshStatusMenu()

        RisperLog.app.info("Risper app shell started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingOverlay.hide()
        stopRecordingRefreshTimer()

        if let recording = audioRecorder.stopRecording() {
            deleteRecording(recording)
        }

        for recording in pendingTranscriptionRecordings.values {
            deleteRecording(recording)
        }
        pendingTranscriptionRecordings.removeAll()

        fallbackHotKeyMonitor.stop()
        functionKeyMonitor.stop()
        asrServerManager.stop()
    }

    func triggerDidBegin(source: TriggerSource) {
        guard activeTrigger == nil else { return }
        guard !isDictationBusy else {
            lastTriggerDescription = "\(source.rawValue) ignored; dictation in progress"
            refreshStatusMenu()
            return
        }

        guard asrServerManager.isReady else {
            dictationStatus = "ASR unavailable"
            lastTriggerDescription = "\(source.rawValue) ignored; ASR not ready"
            asrServerManager.start()
            RisperLog.app.warning("Recording ignored because ASR is not ready")
            refreshStatusMenu()
            return
        }

        activeTrigger = source
        lastTriggerDescription = "\(source.rawValue) began"
        RisperLog.app.info("Trigger began: \(source.rawValue, privacy: .public)")

        do {
            try audioRecorder.startRecording()
            recordingOverlay.show()
            startRecordingRefreshTimer()
        } catch {
            activeTrigger = nil
            recordingOverlay.hide()
            stopRecordingRefreshTimer()
            lastTriggerDescription = "\(source.rawValue) began; recording unavailable"
            RisperLog.app.error("Recording did not start: \(error.localizedDescription, privacy: .public)")
        }

        refreshStatusMenu()
    }

    func triggerDidEnd(source: TriggerSource) {
        guard activeTrigger == source else { return }
        activeTrigger = nil
        recordingOverlay.hide()
        stopRecordingRefreshTimer()

        if let recording = audioRecorder.stopRecording() {
            RisperLog.app.info("Recording stopped after \(recording.duration, privacy: .public) seconds")
            guard shouldTranscribe(recording) else {
                ignoreRecording(recording, source: source)
                return
            }

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

    func copyLastTranscript() {
        guard let lastTranscript else {
            dictationStatus = "No transcript to copy"
            refreshStatusMenu()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if pasteboard.setString(lastTranscript, forType: .string) {
            dictationStatus = "Copied last transcript"
            RisperLog.app.info("Last transcript copied: \(lastTranscript.count, privacy: .public) characters")
        } else {
            dictationStatus = "Copy failed"
            RisperLog.app.error("Unable to copy last transcript")
        }

        refreshStatusMenu()
    }

    func recheckStatus() {
        functionKeyMonitor.start()
        asrServerManager.start()
        refreshStatusMenu()
    }

    func restartASRServer() {
        dictationStatus = "Restarting ASR"
        asrServerManager.restart()
        refreshStatusMenu()
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

    func selectLanguage(_ language: DictationLanguage) {
        guard languageStore.current != language else { return }
        languageStore.current = language
        RisperLog.app.info("Dictation language set to \(language.rawValue, privacy: .public)")
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        statusController.refresh(snapshot: StatusMenuSnapshot(
            appStatus: "Running",
            modelStatus: ModelLocator.statusDescription,
            asrServerStatus: asrServerManager.statusDescription,
            accessibilityStatus: AccessibilityPermission.statusDescription,
            microphoneStatus: MicrophonePermission.statusDescription,
            functionKeyStatus: functionKeyMonitor.statusDescription,
            fallbackStatus: fallbackHotKeyMonitor.statusDescription,
            recordingStatus: audioRecorder.statusDescription,
            dictationStatus: dictationStatus,
            lastRecording: audioRecorder.lastRecordingDescription,
            activeTrigger: activeTriggerDescription,
            lastTrigger: lastTriggerDescription,
            hasLastTranscript: lastTranscript != nil,
            selectedLanguage: languageStore.current
        ))
    }

    private var activeTriggerDescription: String {
        activeTrigger?.rawValue ?? "Idle"
    }

    private func shouldTranscribe(_ recording: RecordingResult) -> Bool {
        guard recording.duration >= minimumTranscriptionDuration else {
            return false
        }

        return recording.peakLevel >= minimumSpeechPeakLevel ||
            recording.averageLevel >= minimumSpeechAverageLevel
    }

    private func ignoreRecording(_ recording: RecordingResult, source: TriggerSource) {
        if recording.duration < minimumTranscriptionDuration {
            dictationStatus = "Recording too short"
            lastTriggerDescription = "\(source.rawValue) ended; ignored short recording"
        } else {
            dictationStatus = "No speech detected"
            lastTriggerDescription = "\(source.rawValue) ended; ignored quiet recording"
        }

        RisperLog.app.info(
            "Recording ignored before ASR: duration \(recording.duration, privacy: .public), peak \(recording.peakLevel, privacy: .public), average \(recording.averageLevel, privacy: .public)"
        )
        deleteRecording(recording)
        refreshStatusMenu()
    }

    private func transcribeAndPaste(recording: RecordingResult, source: TriggerSource) {
        isDictationBusy = true
        dictationStatus = "Transcribing"
        lastTriggerDescription = "\(source.rawValue) ended; transcribing \(recording.url.lastPathComponent)"
        refreshStatusMenu()

        guard asrServerManager.isReady else {
            dictationStatus = "ASR unavailable"
            lastTriggerDescription = "\(source.rawValue) ended; ASR unavailable"
            isDictationBusy = false
            deleteRecording(recording)
            asrServerManager.start()
            refreshStatusMenu()
            return
        }

        pendingTranscriptionRecordings[recording.url] = recording
        asrClient.transcribe(recording: recording, language: languageStore.current) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleTranscriptionResult(result, source: source, recording: recording)
            }
        }
    }

    private func handleTranscriptionResult(
        _ result: Result<String, Error>,
        source: TriggerSource,
        recording: RecordingResult
    ) {
        defer {
            pendingTranscriptionRecordings[recording.url] = nil
            deleteRecording(recording)
            isDictationBusy = false
            refreshStatusMenu()
        }

        switch result {
        case .success(let transcript):
            lastTranscript = transcript
            RisperLog.app.info("Transcription completed: \(transcript.count, privacy: .public) characters")
            paste(transcript, source: source)
        case .failure(let error):
            dictationStatus = dictationFailureStatus(for: error)
            lastTriggerDescription = "\(source.rawValue) ended; transcription failed"
            RisperLog.app.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        }
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

    private func startRecordingRefreshTimer() {
        stopRecordingRefreshTimer()
        recordingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshStatusMenu()
        }
    }

    private func stopRecordingRefreshTimer() {
        recordingRefreshTimer?.invalidate()
        recordingRefreshTimer = nil
    }

    private func deleteRecording(_ recording: RecordingResult) {
        guard FileManager.default.fileExists(atPath: recording.url.path) else { return }

        do {
            try FileManager.default.removeItem(at: recording.url)
            RisperLog.app.info("Temporary recording deleted: \(recording.url.lastPathComponent, privacy: .public)")
        } catch {
            RisperLog.app.error("Unable to delete temporary recording: \(error.localizedDescription, privacy: .public)")
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
