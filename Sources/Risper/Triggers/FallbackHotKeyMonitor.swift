import Carbon
import Foundation

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
            RisperLog.app.error("Unable to install fallback hotkey handler: \(handlerStatus)")
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
            RisperLog.app.error("Unable to register fallback hotkey: \(registerStatus)")
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

private func fourCharacterCode(_ string: String) -> OSType {
    precondition(string.utf8.count == 4)
    return string.utf8.reduce(0) { result, character in
        (result << 8) + OSType(character)
    }
}
