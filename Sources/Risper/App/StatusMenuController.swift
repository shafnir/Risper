import AppKit

protocol StatusMenuControllerDelegate: AnyObject {
    func refreshStatusMenu()
    func requestMicrophonePermission()
    func openPrivacySettings()
}

final class StatusMenuController: NSObject {
    private weak var delegate: StatusMenuControllerDelegate?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let appStateItem = NSMenuItem()
    private let modelItem = NSMenuItem()
    private let asrServerItem = NSMenuItem()
    private let accessibilityItem = NSMenuItem()
    private let microphoneItem = NSMenuItem()
    private let functionKeyItem = NSMenuItem()
    private let fallbackItem = NSMenuItem()
    private let recordingItem = NSMenuItem()
    private let dictationItem = NSMenuItem()
    private let lastRecordingItem = NSMenuItem()
    private let activeTriggerItem = NSMenuItem()
    private let lastTriggerItem = NSMenuItem()

    init(delegate: StatusMenuControllerDelegate) {
        self.delegate = delegate
        super.init()
        configureMenu()
    }

    func refresh(
        accessibilityTrusted: Bool,
        microphoneStatus: String,
        modelStatus: String,
        asrServerStatus: String,
        functionKeyStatus: String,
        fallbackStatus: String,
        recordingStatus: String,
        dictationStatus: String,
        lastRecording: String,
        activeTrigger: String,
        lastTrigger: String
    ) {
        statusItem.button?.title = "Risper"
        appStateItem.title = "App: Running"
        modelItem.title = "Model: \(modelStatus)"
        asrServerItem.title = "ASR Server: \(asrServerStatus)"
        accessibilityItem.title = "Accessibility: \(accessibilityTrusted ? "Granted" : "Required for paste")"
        microphoneItem.title = "Microphone: \(microphoneStatus)"
        functionKeyItem.title = "fn Trigger: \(functionKeyStatus)"
        fallbackItem.title = "Shortcut: \(fallbackStatus)"
        recordingItem.title = "Recording: \(recordingStatus)"
        dictationItem.title = "Dictation: \(dictationStatus)"
        lastRecordingItem.title = "Last Recording: \(lastRecording)"
        activeTriggerItem.title = "Trigger: \(activeTrigger)"
        lastTriggerItem.title = "Last Trigger: \(lastTrigger)"
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(appStateItem)
        menu.addItem(modelItem)
        menu.addItem(asrServerItem)
        menu.addItem(accessibilityItem)
        menu.addItem(microphoneItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(functionKeyItem)
        menu.addItem(fallbackItem)
        menu.addItem(recordingItem)
        menu.addItem(dictationItem)
        menu.addItem(lastRecordingItem)
        menu.addItem(activeTriggerItem)
        menu.addItem(lastTriggerItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Recheck Status", action: #selector(recheckStatus)))
        menu.addItem(menuItem("Request Microphone Permission", action: #selector(requestMicrophonePermission)))
        menu.addItem(menuItem("Open Privacy Settings", action: #selector(openPrivacySettings)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Quit Risper", action: #selector(quit)))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func recheckStatus() {
        delegate?.refreshStatusMenu()
    }

    @objc private func requestMicrophonePermission() {
        delegate?.requestMicrophonePermission()
    }

    @objc private func openPrivacySettings() {
        delegate?.openPrivacySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
