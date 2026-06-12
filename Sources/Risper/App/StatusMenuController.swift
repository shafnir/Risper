import AppKit

struct StatusMenuSnapshot {
    let appStatus: String
    let modelStatus: String
    let asrServerStatus: String
    let accessibilityStatus: String
    let microphoneStatus: String
    let functionKeyStatus: String
    let fallbackStatus: String
    let recordingStatus: String
    let dictationStatus: String
    let lastRecording: String
    let activeTrigger: String
    let lastTrigger: String
    let hasLastTranscript: Bool
    let selectedLanguage: DictationLanguage
    let isRecording: Bool
    let isBusy: Bool
    let accessibilityGranted: Bool
    let microphoneGranted: Bool
    let modelPresent: Bool
    let asrReady: Bool
}

protocol StatusMenuControllerDelegate: AnyObject {
    func copyLastTranscript()
    func recheckStatus()
    func restartASRServer()
    func requestMicrophonePermission()
    func openPrivacySettings()
    func selectLanguage(_ language: DictationLanguage)
}

final class StatusMenuController: NSObject {
    private weak var delegate: StatusMenuControllerDelegate?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let headlineItem = NSMenuItem()
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
    private lazy var copyLastTranscriptItem = menuItem("Copy Last Transcript", action: #selector(copyLastTranscript))
    private lazy var languageItems: [DictationLanguage: NSMenuItem] = makeLanguageItems()

    init(delegate: StatusMenuControllerDelegate) {
        self.delegate = delegate
        super.init()
        configureMenu()
    }

    func refresh(snapshot: StatusMenuSnapshot) {
        updateStatusButton(isRecording: snapshot.isRecording)
        headlineItem.attributedTitle = NSAttributedString(
            string: headlineTitle(for: snapshot),
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        appStateItem.title = "App: \(snapshot.appStatus)"
        modelItem.title = "Model: \(snapshot.modelStatus)"
        asrServerItem.title = "ASR: \(snapshot.asrServerStatus)"
        accessibilityItem.title = "Accessibility: \(snapshot.accessibilityStatus)"
        microphoneItem.title = "Microphone: \(snapshot.microphoneStatus)"
        functionKeyItem.title = "fn Long-Press: \(snapshot.functionKeyStatus)"
        fallbackItem.title = "Fallback Shortcut: \(snapshot.fallbackStatus)"
        recordingItem.title = "Recording: \(snapshot.recordingStatus)"
        dictationItem.title = "Dictation: \(snapshot.dictationStatus)"
        lastRecordingItem.title = "Last Recording: \(snapshot.lastRecording)"
        activeTriggerItem.title = "Active Trigger: \(snapshot.activeTrigger)"
        lastTriggerItem.title = "Last Trigger: \(snapshot.lastTrigger)"
        copyLastTranscriptItem.isEnabled = snapshot.hasLastTranscript

        for (language, item) in languageItems {
            item.state = language == snapshot.selectedLanguage ? .on : .off
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        headlineItem.isEnabled = false
        menu.addItem(headlineItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(languageMenuItem())
        menu.addItem(copyLastTranscriptItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Open Privacy Settings…", action: #selector(openPrivacySettings)))
        menu.addItem(troubleshootingMenuItem())

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Quit Risper", action: #selector(quit)))

        statusItem.menu = menu
    }

    private func troubleshootingMenuItem() -> NSMenuItem {
        let submenu = NSMenu()

        submenu.addItem(sectionHeader("Readiness"))
        submenu.addItem(appStateItem)
        submenu.addItem(modelItem)
        submenu.addItem(asrServerItem)

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(sectionHeader("Permissions"))
        submenu.addItem(accessibilityItem)
        submenu.addItem(microphoneItem)

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(sectionHeader("Trigger And Recording"))
        submenu.addItem(functionKeyItem)
        submenu.addItem(fallbackItem)
        submenu.addItem(recordingItem)
        submenu.addItem(activeTriggerItem)

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(sectionHeader("Last Result"))
        submenu.addItem(dictationItem)
        submenu.addItem(lastRecordingItem)
        submenu.addItem(lastTriggerItem)

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(menuItem("Recheck Status", action: #selector(recheckStatus)))
        submenu.addItem(menuItem("Restart ASR Server", action: #selector(restartASRServer)))
        submenu.addItem(menuItem("Request Microphone Permission", action: #selector(requestMicrophonePermission)))

        let item = NSMenuItem(title: "Troubleshooting", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func headlineTitle(for snapshot: StatusMenuSnapshot) -> String {
        if snapshot.isRecording { return "Recording…" }
        if snapshot.isBusy { return "Transcribing…" }
        if !snapshot.accessibilityGranted || !snapshot.microphoneGranted {
            return "Setup needed — grant permissions"
        }
        if !snapshot.modelPresent { return "Setup needed — model missing" }
        if !snapshot.asrReady { return "Starting…" }
        return "Ready"
    }

    private func updateStatusButton(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        button.title = ""

        let symbolName = isRecording ? "mic.fill" : "mic"
        let description = isRecording ? "Risper — recording" : "Risper"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)

        if isRecording {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            image?.isTemplate = false
            button.image = image?.withSymbolConfiguration(config)
        } else {
            image?.isTemplate = true
            button.image = image
        }
    }

    private func makeLanguageItems() -> [DictationLanguage: NSMenuItem] {
        var items: [DictationLanguage: NSMenuItem] = [:]
        for language in DictationLanguage.allCases {
            let item = NSMenuItem(title: language.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            items[language] = item
        }
        return items
    }

    private func languageMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for language in DictationLanguage.allCases {
            if let item = languageItems[language] {
                submenu.addItem(item)
            }
        }

        let item = NSMenuItem(title: "Dictation Language", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func copyLastTranscript() {
        delegate?.copyLastTranscript()
    }

    @objc private func recheckStatus() {
        delegate?.recheckStatus()
    }

    @objc private func restartASRServer() {
        delegate?.restartASRServer()
    }

    @objc private func requestMicrophonePermission() {
        delegate?.requestMicrophonePermission()
    }

    @objc private func openPrivacySettings() {
        delegate?.openPrivacySettings()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = DictationLanguage(rawValue: rawValue) else {
            return
        }
        delegate?.selectLanguage(language)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
