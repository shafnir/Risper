import AppKit
import ApplicationServices
import AVFoundation
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, TriggerMonitorDelegate, StatusMenuControllerDelegate {
    private lazy var statusController = StatusMenuController(delegate: self)
    private lazy var fallbackHotKeyMonitor = FallbackHotKeyMonitor(delegate: self)
    private let audioRecorder = AudioRecorder()

    private var activeTrigger: TriggerSource?
    private var lastTriggerDescription = "None"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusController.refresh(
            accessibilityTrusted: AXIsProcessTrusted(),
            microphoneStatus: MicrophonePermission.statusDescription,
            modelStatus: ModelLocator.statusDescription,
            asrServerStatus: ASRServerStatus.description,
            functionKeyStatus: FunctionKeyLongPressMonitor.simpleModeStatus,
            fallbackStatus: "Starting",
            recordingStatus: audioRecorder.statusDescription,
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
        activeTrigger = source
        lastTriggerDescription = "\(source.rawValue) began"
        RisperLog.app.info("Trigger began: \(source.rawValue, privacy: .public)")

        do {
            try audioRecorder.startRecording()
        } catch {
            lastTriggerDescription = "\(source.rawValue) began; recording unavailable"
            RisperLog.app.error("Recording did not start: \(error.localizedDescription, privacy: .public)")
        }

        refreshStatusMenu()
    }

    func triggerDidEnd(source: TriggerSource) {
        guard activeTrigger == source else { return }
        activeTrigger = nil

        if let recording = audioRecorder.stopRecording() {
            lastTriggerDescription = "\(source.rawValue) ended; saved \(recording.url.lastPathComponent)"
        } else {
            lastTriggerDescription = "\(source.rawValue) ended"
        }

        RisperLog.app.info("Trigger ended: \(source.rawValue, privacy: .public)")
        refreshStatusMenu()
    }

    func triggerMonitorStatusDidChange() {
        refreshStatusMenu()
    }

    func refreshStatusMenu() {
        statusController.refresh(
            accessibilityTrusted: AXIsProcessTrusted(),
            microphoneStatus: MicrophonePermission.statusDescription,
            modelStatus: ModelLocator.statusDescription,
            asrServerStatus: ASRServerStatus.description,
            functionKeyStatus: FunctionKeyLongPressMonitor.simpleModeStatus,
            fallbackStatus: fallbackHotKeyMonitor.statusDescription,
            recordingStatus: audioRecorder.statusDescription,
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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var activeTriggerDescription: String {
        activeTrigger?.rawValue ?? "Idle"
    }
}
