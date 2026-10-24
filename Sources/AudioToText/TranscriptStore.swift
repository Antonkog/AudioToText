import Foundation

enum TranscriptStore {
    static func save(_ text: String, suggestedName: String, now: Date = Date()) throws -> URL {
        let folder = try transcriptsFolder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        let base = TranscriptUtilities.safeBaseName(suggestedName)
        let filename = "\(base) — \(formatter.string(from: now)).txt"
        let output = folder.appendingPathComponent(filename)
        try text.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    static func transcriptsFolder() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = documents.appendingPathComponent("AudioToText", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
