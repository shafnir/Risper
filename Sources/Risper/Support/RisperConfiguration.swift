import Foundation
import OSLog

enum RisperConfiguration {
    static let bundleIdentifier = "com.risper.Risper"
    static let functionHoldThreshold: TimeInterval = 0.3
    static let recordingSampleRate = 16_000.0
    static let asrHost = "127.0.0.1"
    static let asrPort = 8178

    static let asrHealthURL: URL = {
        var components = URLComponents()
        components.scheme = "http"
        components.host = asrHost
        components.port = asrPort
        components.path = "/health"

        guard let url = components.url else {
            preconditionFailure("Invalid Risper ASR health URL")
        }

        return url
    }()

    static let asrInferenceURL: URL = {
        var components = URLComponents()
        components.scheme = "http"
        components.host = asrHost
        components.port = asrPort
        components.path = "/inference"

        guard let url = components.url else {
            preconditionFailure("Invalid Risper ASR inference URL")
        }

        return url
    }()

    static let modelURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Risper/Models/ivrit-large-v3-turbo/ggml-model.bin")

    static let recordingsDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/Risper/recordings", isDirectory: true)
}

enum RisperLog {
    static let app = Logger(subsystem: RisperConfiguration.bundleIdentifier, category: "App")
}
