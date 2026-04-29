import Foundation

enum TranscriptCleaner {
    private static let timestampPatterns = [
        #"\[[0-9:.]+\s*(?:-->|-)\s*[0-9:.]+\]"#,
        #"\([0-9:.]+\s*(?:-->|-)\s*[0-9:.]+\)"#,
        #"\[[0-9:.]+\]"#,
        #"\([0-9:.]+\)"#
    ]

    static func clean(_ transcript: String) -> String {
        var cleaned = transcript

        for pattern in timestampPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
