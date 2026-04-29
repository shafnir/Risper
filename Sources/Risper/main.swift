import AppKit
import ApplicationServices
import AVFoundation
import Carbon
import CoreGraphics
import Foundation
import OSLog

private let bundleIdentifier = "com.risper.Risper"
private let functionHoldThreshold: TimeInterval = 0.3

private let logger = Logger(subsystem: bundleIdentifier, category: "App")

enum TriggerSource: String {
    case functionKey = "fn long-press"
    case fallbackHotKey = "Control+Option+Space"
}

protocol TriggerMonitorDelegate: AnyObject {
    func triggerDidBegin(source: TriggerSource)
    func triggerDidEnd(source: TriggerSource)
    func triggerMonitorStatusDidChange()
}

final class AppDelegate: NSObject, NSApplicationDelegate, TriggerMonitorDelegate {
    private lazy var statusController = StatusMenuController(delegate: self)
    private lazy var fallbackHotKeyMonitor = FallbackHotKeyMonitor(delegate: self)

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
            activeTrigger: activeTriggerDescription,
            lastTrigger: lastTriggerDescription
        )

        fallbackHotKeyMonitor.start()
        refreshStatusMenu()
        logger.info("Risper app shell started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        fallbackHotKeyMonitor.stop()
    }

    func triggerDidBegin(source: TriggerSource) {
        guard activeTrigger == nil else { return }
        activeTrigger = source
        lastTriggerDescription = "\(source.rawValue) began"
        logger.info("Trigger began: \(source.rawValue, privacy: .public)")
        refreshStatusMenu()
    }

    func triggerDidEnd(source: TriggerSource) {
        guard activeTrigger == source else { return }
        activeTrigger = nil
        lastTriggerDescription = "\(source.rawValue) ended"
        logger.info("Trigger ended: \(source.rawValue, privacy: .public)")
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

final class StatusMenuController: NSObject {
    private weak var delegate: AppDelegate?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let appStateItem = NSMenuItem()
    private let modelItem = NSMenuItem()
    private let asrServerItem = NSMenuItem()
    private let accessibilityItem = NSMenuItem()
    private let microphoneItem = NSMenuItem()
    private let functionKeyItem = NSMenuItem()
    private let fallbackItem = NSMenuItem()
    private let activeTriggerItem = NSMenuItem()
    private let lastTriggerItem = NSMenuItem()

    init(delegate: AppDelegate) {
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
        activeTrigger: String,
        lastTrigger: String
    ) {
        statusItem.button?.title = "Risper"
        appStateItem.title = "App: Running"
        modelItem.title = "Model: \(modelStatus)"
        asrServerItem.title = "ASR Server: \(asrServerStatus)"
        accessibilityItem.title = "Accessibility: \(accessibilityTrusted ? "Granted" : "Not needed yet")"
        microphoneItem.title = "Microphone: \(microphoneStatus)"
        functionKeyItem.title = "fn Trigger: \(functionKeyStatus)"
        fallbackItem.title = "Shortcut: \(fallbackStatus)"
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

final class FunctionKeyLongPressMonitor {
    static let simpleModeStatus = "Off (using shortcut)"

    private weak var delegate: TriggerMonitorDelegate?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdWorkItem: DispatchWorkItem?
    private var isFunctionKeyDown = false
    private var isTriggerActive = false
    private(set) var statusDescription = "Not started"

    init(delegate: TriggerMonitorDelegate) {
        self.delegate = delegate
    }

    func start() {
        stop()

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: functionKeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            statusDescription = "Unavailable; grant Accessibility/Input Monitoring"
            delegate?.triggerMonitorStatusDidChange()
            logger.warning("Unable to create fn-key event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        statusDescription = "Waiting for long-press"
        delegate?.triggerMonitorStatusDidChange()
    }

    func stop() {
        holdWorkItem?.cancel()
        holdWorkItem = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isFunctionKeyDown = false
        isTriggerActive = false
        statusDescription = "Stopped"
    }

    fileprivate func handle(eventType: CGEventType, event: CGEvent) {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        guard eventType == .flagsChanged else { return }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let fnFlagIsDown = event.flags.contains(.maskSecondaryFn)
        let isFunctionEvent = keyCode == UInt16(kVK_Function) || fnFlagIsDown != isFunctionKeyDown
        guard isFunctionEvent else { return }

        if fnFlagIsDown {
            armFunctionTrigger()
        } else {
            releaseFunctionTrigger()
        }
    }

    private func armFunctionTrigger() {
        guard !isFunctionKeyDown else { return }
        isFunctionKeyDown = true
        statusDescription = "Armed"
        delegate?.triggerMonitorStatusDidChange()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isFunctionKeyDown, !self.isTriggerActive else { return }
            self.isTriggerActive = true
            self.statusDescription = "Active"
            self.delegate?.triggerDidBegin(source: .functionKey)
            self.delegate?.triggerMonitorStatusDidChange()
        }
        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + functionHoldThreshold, execute: workItem)
    }

    private func releaseFunctionTrigger() {
        guard isFunctionKeyDown else { return }
        isFunctionKeyDown = false
        holdWorkItem?.cancel()
        holdWorkItem = nil

        if isTriggerActive {
            isTriggerActive = false
            delegate?.triggerDidEnd(source: .functionKey)
        }

        statusDescription = "Waiting for long-press"
        delegate?.triggerMonitorStatusDidChange()
    }
}

private let functionKeyEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<FunctionKeyLongPressMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handle(eventType: type, event: event)
    return Unmanaged.passUnretained(event)
}

final class FallbackHotKeyMonitor {
    private weak var delegate: TriggerMonitorDelegate?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isActive = false
    private(set) var statusDescription = "Not started"

    private let hotKeyID = EventHotKeyID(signature: fourCharacterCode("RSPR"), id: 1)

    init(delegate: TriggerMonitorDelegate) {
        self.delegate = delegate
    }

    func start() {
        stop()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            fallbackHotKeyEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard handlerStatus == noErr else {
            statusDescription = "Handler failed (\(handlerStatus))"
            delegate?.triggerMonitorStatusDidChange()
            logger.error("Unable to install fallback hotkey handler: \(handlerStatus)")
            return
        }

        var registeredHotKey: EventHotKeyRef?
        let modifiers = UInt32(controlKey | optionKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyNoOptions),
            &registeredHotKey
        )

        guard registerStatus == noErr else {
            statusDescription = "Unavailable (\(registerStatus))"
            delegate?.triggerMonitorStatusDidChange()
            logger.error("Unable to register fallback hotkey: \(registerStatus)")
            return
        }

        hotKeyRef = registeredHotKey
        statusDescription = "Registered"
        delegate?.triggerMonitorStatusDidChange()
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        hotKeyRef = nil
        handlerRef = nil
        isActive = false
        statusDescription = "Stopped"
    }

    fileprivate func handle(event: EventRef?) -> OSStatus {
        guard let event else { return noErr }

        var eventHotKeyID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyID
        )

        guard parameterStatus == noErr,
              eventHotKeyID.signature == hotKeyID.signature,
              eventHotKeyID.id == hotKeyID.id else {
            return noErr
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            guard !isActive else { return noErr }
            isActive = true
            delegate?.triggerDidBegin(source: .fallbackHotKey)
        case UInt32(kEventHotKeyReleased):
            guard isActive else { return noErr }
            isActive = false
            delegate?.triggerDidEnd(source: .fallbackHotKey)
        default:
            break
        }

        return noErr
    }
}

private let fallbackHotKeyEventHandler: EventHandlerUPP = { _, event, refcon in
    guard let refcon else { return noErr }
    let monitor = Unmanaged<FallbackHotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(event: event)
}

enum ModelLocator {
    static let modelURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Risper/Models/ivrit-large-v3-turbo/ggml-model.bin")
    }()

    static var statusDescription: String {
        FileManager.default.fileExists(atPath: modelURL.path) ? "Present" : "Missing"
    }
}

enum MicrophonePermission {
    static var statusDescription: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }
}

enum ASRServerStatus {
    static var description: String {
        "Not configured"
    }
}

private func fourCharacterCode(_ string: String) -> OSType {
    precondition(string.utf8.count == 4)
    return string.utf8.reduce(0) { result, character in
        (result << 8) + OSType(character)
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
