import Foundation

enum ModelRepositories {
    static let whisper = "RedHotAnton/whisperkit-coreml"
    static let textToSpeech = "RedHotAnton/ttskit-coreml"
    static let tokenizer = "RedHotAnton/Qwen3-0.6B"

    static let legacyWhisper = "argmaxinc/whisperkit-coreml"
    static let legacyTextToSpeech = "argmaxinc/ttskit-coreml"
    static let legacyTokenizer = "Qwen/Qwen3-0.6B"

    static let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json", "config.json"]

    static func downloadURL(repository: String, filename: String) -> URL? {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(filename)")
    }

    static var documentsDirectory: URL? {
        try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    static func cacheFolder(for repository: String, under documentsDirectory: URL) -> URL {
        documentsDirectory
            .appendingPathComponent("huggingface/models", isDirectory: true)
            .appendingPathComponent(repository, isDirectory: true)
    }

    static func cacheFolders(
        primary: String,
        legacy: String,
        under documentsDirectory: URL
    ) -> [URL] {
        [primary, legacy].map { cacheFolder(for: $0, under: documentsDirectory) }
    }
}
