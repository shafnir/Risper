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
        statusItem.button?.title = snapshot.recordingStatus.hasPrefix("Recording") ? "Risper REC" : "Risper"
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

        menu.addItem(sectionHeader("Readiness"))
        menu.addItem(appStateItem)
        menu.addItem(modelItem)
        menu.addItem(asrServerItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(sectionHeader("Permissions"))
        menu.addItem(accessibilityItem)
        menu.addItem(microphoneItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(sectionHeader("Trigger And Recording"))
        menu.addItem(functionKeyItem)
        menu.addItem(fallbackItem)
        menu.addItem(recordingItem)
        menu.addItem(activeTriggerItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(sectionHeader("Last Result"))
        menu.addItem(dictationItem)
        menu.addItem(lastRecordingItem)
        menu.addItem(lastTriggerItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(sectionHeader("Dictation Language"))
        menu.addItem(languageMenuItem())

        menu.addItem(NSMenuItem.separator())
        menu.addItem(sectionHeader("Actions"))
        menu.addItem(copyLastTranscriptItem)
        menu.addItem(menuItem("Recheck Status", action: #selector(recheckStatus)))
        menu.addItem(menuItem("Restart ASR Server", action: #selector(restartASRServer)))
        menu.addItem(menuItem("Request Microphone Permission", action: #selector(requestMicrophonePermission)))
        menu.addItem(menuItem("Open Privacy Settings", action: #selector(openPrivacySettings)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Quit Risper", action: #selector(quit)))

        statusItem.menu = menu
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

        let item = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
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
