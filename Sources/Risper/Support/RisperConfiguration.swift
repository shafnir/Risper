import Foundation
import OSLog

enum RisperConfiguration {
    static let bundleIdentifier = "com.risper.Risper"
    static let functionHoldThreshold: TimeInterval = 0.3
    static let recordingSampleRate = 16_000.0

    static let modelURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Risper/Models/ivrit-large-v3-turbo/ggml-model.bin")

    static let recordingsDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/Risper/recordings", isDirectory: true)
}

enum RisperLog {
    static let app = Logger(subsystem: RisperConfiguration.bundleIdentifier, category: "App")
}
