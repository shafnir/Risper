import Carbon
import CoreGraphics
import Foundation

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
            RisperLog.app.warning("Unable to create fn-key event tap")
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
