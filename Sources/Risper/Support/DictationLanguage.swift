import Foundation

/// User-selectable dictation language sent to the local whisper.cpp server.
///
/// `auto` lets Whisper detect the spoken language per recording; the explicit
/// cases force a single language and skip detection.
enum DictationLanguage: String, CaseIterable {
    case auto
    case hebrew
    case english

    /// Language argument understood by the whisper.cpp `/inference` endpoint.
    var whisperCode: String {
        switch self {
        case .auto:
            return "auto"
        case .hebrew:
            return "he"
        case .english:
            return "en"
        }
    }

    var displayName: String {
        switch self {
        case .auto:
            return "Auto Detect"
        case .hebrew:
            return "Hebrew"
        case .english:
            return "English"
        }
    }
}

/// Single source of truth for the selected dictation language, persisted across
/// launches in `UserDefaults`. Defaults to Hebrew to preserve prior behavior.
final class DictationLanguageStore {
    private let defaults: UserDefaults
    private let storageKey = "RisperDictationLanguage"
    private let defaultLanguage: DictationLanguage = .hebrew

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: DictationLanguage {
        get {
            guard let rawValue = defaults.string(forKey: storageKey),
                  let language = DictationLanguage(rawValue: rawValue) else {
                return defaultLanguage
            }
            return language
        }
        set {
            defaults.set(newValue.rawValue, forKey: storageKey)
        }
    }
}
