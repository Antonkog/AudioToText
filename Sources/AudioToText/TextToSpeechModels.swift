import Foundation
import TTSKit

enum AppMode: String, CaseIterable, Identifiable {
    case audioToText
    case textToAudio

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .audioToText: "mode.audio_to_text"
        case .textToAudio: "mode.text_to_audio"
        }
    }
}

enum TTSModelOption: String, CaseIterable, Identifiable, Sendable {
    case compact = "0.6b"
    case quality = "1.7b"

    var id: String { rawValue }

    var variant: TTSModelVariant {
        switch self {
        case .compact: .qwen3TTS_0_6b
        case .quality: .qwen3TTS_1_7b
        }
    }

    var titleKey: String {
        switch self {
        case .compact: "tts.model.compact"
        case .quality: "tts.model.quality"
        }
    }

    var detailKey: String {
        switch self {
        case .compact: "tts.model.compact_detail"
        case .quality: "tts.model.quality_detail"
        }
    }

    var downloadSize: String {
        switch self {
        case .compact: "~1 GB"
        case .quality: "~2.2 GB"
        }
    }

    var estimatedDownloadBytes: Int64 {
        switch self {
        case .compact: 1_000_000_000
        case .quality: 2_200_000_000
        }
    }

    var recommendedMemoryBytes: UInt64 {
        switch self {
        case .compact: 8 * 1_024 * 1_024 * 1_024
        case .quality: 16 * 1_024 * 1_024 * 1_024
        }
    }

    static var localRepositoryFolder: URL? {
        guard let documents = ModelRepositories.documentsDirectory else { return nil }
        return ModelRepositories.cacheFolder(for: ModelRepositories.textToSpeech, under: documents)
    }

    static var localRepositoryFolders: [URL] {
        guard let documents = ModelRepositories.documentsDirectory else { return [] }
        return ModelRepositories.cacheFolders(
            primary: ModelRepositories.textToSpeech,
            legacy: ModelRepositories.legacyTextToSpeech,
            under: documents
        )
    }

    static var localTokenizerFolder: URL? {
        guard let documents = ModelRepositories.documentsDirectory else { return nil }
        return ModelRepositories.cacheFolder(for: ModelRepositories.tokenizer, under: documents)
    }

    static var localTokenizerFolders: [URL] {
        guard let documents = ModelRepositories.documentsDirectory else { return [] }
        return ModelRepositories.cacheFolders(
            primary: ModelRepositories.tokenizer,
            legacy: ModelRepositories.legacyTokenizer,
            under: documents
        )
    }

    static func downloadedRepositoryFolder(for model: TTSModelOption) -> URL? {
        localRepositoryFolders.first { isDownloaded(in: $0, model: model) }
    }

    static var downloadedTokenizerFolder: URL? {
        localTokenizerFolders.first(where: isTokenizerDownloaded(in:))
    }

    var isDownloaded: Bool {
        guard
            let folder = Self.downloadedRepositoryFolder(for: self),
            let tokenizerFolder = Self.downloadedTokenizerFolder
        else { return false }
        return Self.isDownloaded(in: folder, tokenizerFolder: tokenizerFolder, model: self)
    }

    static func isDownloaded(
        in folder: URL,
        tokenizerFolder: URL,
        model: TTSModelOption
    ) -> Bool {
        isDownloaded(in: folder, model: model) && isTokenizerDownloaded(in: tokenizerFolder)
    }

    static func isDownloaded(in folder: URL, model: TTSModelOption) -> Bool {
        let config = TTSKitConfig(model: model.variant, modelFolder: folder)
        let components: [(String, String)] = [
            ("text_projector", config.textProjectorVariant),
            ("code_embedder", config.codeEmbedderVariant),
            ("multi_code_embedder", config.multiCodeEmbedderVariant),
            ("code_decoder", config.codeDecoderVariant),
            ("multi_code_decoder", config.multiCodeDecoderVariant),
            ("speech_decoder", config.speechDecoderVariant)
        ]
        return components.allSatisfy { component, variant in
            guard let modelURL = config.modelURL(component: component, variant: variant) else { return false }
            return isNonemptyFile(at: modelURL.appendingPathComponent("weights/weight.bin"))
        }
    }

    static func isTokenizerDownloaded(in folder: URL) -> Bool {
        ModelRepositories.tokenizerFiles.allSatisfy { filename in
            let file = folder.appendingPathComponent(filename)
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                return false
            }
            return values.isRegularFile == true && (values.fileSize ?? 0) > 0
        }
    }

    private static func isNonemptyFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return false
        }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }
}

enum TTSSpeechLanguage: String, CaseIterable, Identifiable, Sendable {
    case english, chinese, japanese, korean, german, french, russian, portuguese, spanish, italian

    var id: String { rawValue }

    var titleKey: String { "tts.language.\(rawValue)" }
}

enum TTSVoice: String, CaseIterable, Identifiable, Sendable {
    case ryan, aiden
    case onoAnna = "ono-anna"
    case sohee, eric, dylan, serena, vivian
    case uncleFu = "uncle-fu"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ryan: "Ryan"
        case .aiden: "Aiden"
        case .onoAnna: "Ono Anna"
        case .sohee: "Sohee"
        case .eric: "Eric"
        case .dylan: "Dylan"
        case .serena: "Serena"
        case .vivian: "Vivian"
        case .uncleFu: "Uncle Fu"
        }
    }
}

struct SystemCompatibility: Equatable, Sendable {
    let isAppleSilicon: Bool
    let operatingSystemMajorVersion: Int
    let physicalMemoryBytes: UInt64
    let freeDiskBytes: Int64
    let model: TTSModelOption

    var isSupported: Bool { isAppleSilicon && operatingSystemMajorVersion >= 15 && hasMinimumDisk }
    var shouldWarnMemory: Bool { physicalMemoryBytes < model.recommendedMemoryBytes }
    var hasMinimumDisk: Bool { freeDiskBytes >= model.estimatedDownloadBytes + 1_000_000_000 }
    var hasLowDiskHeadroom: Bool {
        freeDiskBytes < (model.estimatedDownloadBytes * 2) + 2_000_000_000
    }
    var memoryGB: Int { Int((physicalMemoryBytes + 536_870_911) / 1_073_741_824) }
    var freeDiskDescription: String {
        ByteCountFormatter.string(fromByteCount: freeDiskBytes, countStyle: .file)
    }

    static func current(for model: TTSModelOption) -> SystemCompatibility {
        #if arch(arm64)
        let isAppleSilicon = true
        #else
        let isAppleSilicon = false
        #endif
        let home = FileManager.default.homeDirectoryForCurrentUser
        let capacity = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return SystemCompatibility(
            isAppleSilicon: isAppleSilicon,
            operatingSystemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            freeDiskBytes: capacity,
            model: model
        )
    }
}

struct SpeechGenerationRequest: Equatable, Sendable {
    let text: String
    let model: TTSModelOption
    let language: TTSSpeechLanguage
    let voice: TTSVoice
}

struct GeneratedSpeech: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let duration: Double
    let request: SpeechGenerationRequest
}
