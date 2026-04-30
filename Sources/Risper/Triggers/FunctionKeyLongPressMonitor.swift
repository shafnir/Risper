import AppKit
import Carbon
import Foundation

final class FunctionKeyLongPressMonitor {
    static let simpleModeStatus = "Off (using shortcut)"

    private weak var delegate: TriggerMonitorDelegate?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var holdWorkItem: DispatchWorkItem?
    private var isFunctionKeyDown = false
    private var isTriggerActive = false
    private(set) var statusDescription = "Not started"

    init(delegate: TriggerMonitorDelegate) {
        self.delegate = delegate
    }

    func start() {
        stop()

        guard AccessibilityPermission.isTrusted else {
            statusDescription = "Accessibility required"
            delegate?.triggerMonitorStatusDidChange()
            RisperLog.app.warning("fn-key monitor requires Accessibility permission")
            return
        }

        statusDescription = "Starting"
        delegate?.triggerMonitorStatusDidChange()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFunctionKeyEvent(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFunctionKeyEvent(event)
        }

        guard globalMonitor != nil else {
            stop()
            statusDescription = "Unavailable; grant Accessibility"
            delegate?.triggerMonitorStatusDidChange()
            RisperLog.app.warning("Unable to start fn-key global event monitor")
            return
        }

        statusDescription = "Waiting for long-press"
        delegate?.triggerMonitorStatusDidChange()
        RisperLog.app.info("fn-key monitor started with Accessibility event monitoring")
    }

    func stop() {
        holdWorkItem?.cancel()
        holdWorkItem = nil

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        globalMonitor = nil
        localMonitor = nil
        isFunctionKeyDown = false
        isTriggerActive = false
        statusDescription = "Stopped"
    }

    private func handleFunctionKeyEvent(_ event: NSEvent) {
        let fnFlagIsDown = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.function)
        let keyCode = event.keyCode

        DispatchQueue.main.async { [weak self] in
            self?.handleFunctionKeyState(keyCode: keyCode, fnFlagIsDown: fnFlagIsDown)
        }
    }

    private func handleFunctionKeyState(keyCode: UInt16, fnFlagIsDown: Bool) {
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
        RisperLog.app.info("fn-key long-press armed")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isFunctionKeyDown, !self.isTriggerActive else { return }
            self.isTriggerActive = true
            self.statusDescription = "Active"
            RisperLog.app.info("fn-key long-press active")
            self.delegate?.triggerDidBegin(source: .functionKey)
            self.delegate?.triggerMonitorStatusDidChange()
        }
        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + RisperConfiguration.functionHoldThreshold,
            execute: workItem
        )
    }

    private func releaseFunctionTrigger() {
        guard isFunctionKeyDown else { return }
        isFunctionKeyDown = false
        holdWorkItem?.cancel()
        holdWorkItem = nil

        if isTriggerActive {
            isTriggerActive = false
            delegate?.triggerDidEnd(source: .functionKey)
            RisperLog.app.info("fn-key long-press released")
        }

        statusDescription = "Waiting for long-press"
        delegate?.triggerMonitorStatusDidChange()
    }
}
