import Foundation

enum ModelLocator {
    static let modelURL = RisperConfiguration.modelURL

    static var statusDescription: String {
        FileManager.default.fileExists(atPath: modelURL.path) ? "Present" : "Missing"
    }
}

enum ASRServerStatus {
    static var description: String {
        "Assumed at \(RisperConfiguration.asrHost):\(RisperConfiguration.asrPort)"
    }
}
