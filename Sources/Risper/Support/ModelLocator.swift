import Foundation

enum ModelLocator {
    static let modelURL = RisperConfiguration.modelURL

    static var statusDescription: String {
        FileManager.default.fileExists(atPath: modelURL.path) ? "Present" : "Missing"
    }
}
