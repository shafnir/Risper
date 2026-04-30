import AppKit
import ApplicationServices
import Carbon
import Foundation

enum TextInjectorError: LocalizedError {
    case accessibilityRequired
    case pasteboardWriteFailed
    case pasteEventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            return "Accessibility permission is required for paste insertion"
        case .pasteboardWriteFailed:
            return "Unable to write transcript to the pasteboard"
        case .pasteEventCreationFailed:
            return "Unable to create paste keyboard events"
        }
    }
}

final class TextInjector {
    private struct PasteboardSnapshot {
        struct Item {
            let dataByType: [(type: NSPasteboard.PasteboardType, data: Data)]
        }

        let items: [Item]

        static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
            let items = (pasteboard.pasteboardItems ?? []).compactMap { item -> Item? in
                let dataByType = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                    guard let data = item.data(forType: type) else {
                        return nil
                    }

                    return (type, data)
                }

                guard !dataByType.isEmpty else {
                    return nil
                }

                return Item(dataByType: dataByType)
            }

            return PasteboardSnapshot(items: items)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()

            guard !items.isEmpty else {
                return
            }

            let restoredItems = items.map { snapshotItem in
                let item = NSPasteboardItem()

                for entry in snapshotItem.dataByType {
                    item.setData(entry.data, forType: entry.type)
                }

                return item
            }

            pasteboard.writeObjects(restoredItems)
        }
    }

    private static let markerType = NSPasteboard.PasteboardType("\(RisperConfiguration.bundleIdentifier).temporary-transcript")
    private let restoreDelay: TimeInterval

    init(restoreDelay: TimeInterval = 0.6) {
        self.restoreDelay = restoreDelay
    }

    func paste(_ text: String) throws {
        guard AccessibilityPermission.requestIfNeeded() else {
            throw TextInjectorError.accessibilityRequired
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let temporaryToken = UUID().uuidString

        try writeTemporary(text: text, token: temporaryToken, to: pasteboard, restoring: snapshot)
        let temporaryChangeCount = pasteboard.changeCount

        do {
            try postPasteShortcut()
        } catch {
            snapshot.restore(to: pasteboard)
            throw error
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            guard pasteboard.changeCount == temporaryChangeCount,
                  Self.temporaryToken(on: pasteboard) == temporaryToken else {
                return
            }

            snapshot.restore(to: pasteboard)
        }
    }

    private func writeTemporary(
        text: String,
        token: String,
        to pasteboard: NSPasteboard,
        restoring snapshot: PasteboardSnapshot
    ) throws {
        let item = NSPasteboardItem()
        let wroteString = item.setString(text, forType: .string)
        let wroteMarker = item.setString(token, forType: Self.markerType)

        guard wroteString, wroteMarker else {
            throw TextInjectorError.pasteboardWriteFailed
        }

        pasteboard.clearContents()

        guard pasteboard.writeObjects([item]) else {
            snapshot.restore(to: pasteboard)
            throw TextInjectorError.pasteboardWriteFailed
        }
    }

    private func postPasteShortcut() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            throw TextInjectorError.pasteEventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func temporaryToken(on pasteboard: NSPasteboard) -> String? {
        pasteboard.pasteboardItems?.first?.string(forType: markerType)
    }
}
