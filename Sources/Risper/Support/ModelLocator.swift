import Foundation

enum ModelLocator {
    private static let bundledModelRelativePath = "Models/ivrit-large-v3-turbo/ggml-model.bin"
    static let applicationSupportModelURL = RisperConfiguration.modelURL

    static var modelURL: URL {
        resolveModelURL()
    }

    static var isPresent: Bool {
        existingModelURL() != nil
    }

    static var statusDescription: String {
        guard let existingModelURL = existingModelURL() else {
            return "Missing"
        }

        if let bundledModelURL,
           existingModelURL.standardizedFileURL == bundledModelURL.standardizedFileURL {
            return "Present (bundled)"
        }

        return "Present"
    }

    static func resolveModelURL(fileManager: FileManager = .default) -> URL {
        existingModelURL(fileManager: fileManager) ?? applicationSupportModelURL
    }

    private static var bundledModelURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent(bundledModelRelativePath)
    }

    private static func existingModelURL(fileManager: FileManager = .default) -> URL? {
        modelCandidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private static var modelCandidates: [URL] {
        var candidates: [URL] = []

        if let bundledModelURL {
            candidates.append(bundledModelURL)
        }

        candidates.append(applicationSupportModelURL)
        return candidates
    }
}
