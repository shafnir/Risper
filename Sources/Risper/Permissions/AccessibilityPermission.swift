import ApplicationServices
import Foundation

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var statusDescription: String {
        isTrusted ? "Granted" : "Required for paste/fn"
    }

    @discardableResult
    static func requestIfNeeded() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [
            promptKey: true
        ]

        return AXIsProcessTrustedWithOptions(options)
    }
}
