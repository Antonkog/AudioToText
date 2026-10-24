import Foundation

enum TranscriptUtilities {
    static func cleaned(_ fragments: [String]) -> String {
        fragments
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func safeBaseName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let parts = value.components(separatedBy: invalid)
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "-")
        return joined.isEmpty ? "Transcript" : joined
    }
}
