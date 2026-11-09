import Foundation
import Testing
import TTSKit
@testable import AudioToText

struct TextToSpeechConfigurationTests {
    @Test func runtimeRepositoriesUsePublicMirrorsAndKeepLegacyCacheOrder() throws {
        #expect(ModelRepositories.whisper == "RedHotAnton/whisperkit-coreml")
        #expect(ModelRepositories.textToSpeech == "RedHotAnton/ttskit-coreml")
        #expect(ModelRepositories.tokenizer == "RedHotAnton/Qwen3-0.6B")

        let documents = URL(fileURLWithPath: "/tmp/AudioToText-documents", isDirectory: true)
        let folders = ModelRepositories.cacheFolders(
            primary: ModelRepositories.textToSpeech,
            legacy: ModelRepositories.legacyTextToSpeech,
            under: documents
        )
        #expect(folders.map(\.path) == [
            "/tmp/AudioToText-documents/huggingface/models/RedHotAnton/ttskit-coreml",
            "/tmp/AudioToText-documents/huggingface/models/argmaxinc/ttskit-coreml"
        ])
        #expect(
            ModelRepositories.downloadURL(
                repository: ModelRepositories.tokenizer,
                filename: "tokenizer.json"
            )?.absoluteString
            == "https://huggingface.co/RedHotAnton/Qwen3-0.6B/resolve/main/tokenizer.json"
        )
    }

    @Test func modelCatalogMatchesReleaseMetadata() {
        #expect(TTSModelOption.allCases == [.compact, .quality])
        #expect(TTSModelOption.compact.rawValue == "0.6b")
        #expect(TTSModelOption.compact.downloadSize == "~1 GB")
        #expect(TTSModelOption.compact.estimatedDownloadBytes == 1_000_000_000)
        #expect(TTSModelOption.quality.rawValue == "1.7b")
        #expect(TTSModelOption.quality.downloadSize == "~2.2 GB")
        #expect(TTSModelOption.quality.estimatedDownloadBytes == 2_200_000_000)
    }

    @Test func voiceAndLanguageCatalogsAreComplete() {
        #expect(TTSSpeechLanguage.allCases.count == 10)
        #expect(TTSSpeechLanguage.allCases.first == .english)
        #expect(TTSSpeechLanguage.allCases.last == .italian)
        #expect(TTSVoice.allCases.count == 9)
        #expect(TTSVoice.allCases.first == .ryan)
        #expect(TTSVoice.uncleFu.rawValue == "uncle-fu")
    }

    @Test func persistedEnumValuesRoundTripAndDefaultsAreStable() {
        #expect(AppMode(rawValue: AppMode.textToAudio.rawValue) == .textToAudio)
        #expect(TTSModelOption(rawValue: TTSModelOption.compact.rawValue) == .compact)
        #expect(TTSSpeechLanguage(rawValue: TTSSpeechLanguage.russian.rawValue) == .russian)
        #expect(TTSVoice(rawValue: TTSVoice.ryan.rawValue) == .ryan)
    }

    @Test func compatibilityAppliesArchitectureOSMemoryAndDiskRules() {
        let gib = UInt64(1_024 * 1_024 * 1_024)
        let healthyCompact = SystemCompatibility(
            isAppleSilicon: true,
            operatingSystemMajorVersion: 15,
            physicalMemoryBytes: 8 * gib,
            freeDiskBytes: 8_000_000_000,
            model: .compact
        )
        #expect(healthyCompact.isSupported)
        #expect(!healthyCompact.shouldWarnMemory)
        #expect(!healthyCompact.hasLowDiskHeadroom)

        let lowMemoryQuality = SystemCompatibility(
            isAppleSilicon: true,
            operatingSystemMajorVersion: 15,
            physicalMemoryBytes: 8 * gib,
            freeDiskBytes: 8_000_000_000,
            model: .quality
        )
        #expect(lowMemoryQuality.isSupported)
        #expect(lowMemoryQuality.shouldWarnMemory)

        let sixteenGBQuality = SystemCompatibility(
            isAppleSilicon: true,
            operatingSystemMajorVersion: 15,
            physicalMemoryBytes: 16 * gib,
            freeDiskBytes: 8_000_000_000,
            model: .quality
        )
        #expect(!sixteenGBQuality.shouldWarnMemory)

        #expect(!SystemCompatibility(
            isAppleSilicon: false,
            operatingSystemMajorVersion: 15,
            physicalMemoryBytes: 16 * gib,
            freeDiskBytes: 8_000_000_000,
            model: .compact
        ).isSupported)
        #expect(!SystemCompatibility(
            isAppleSilicon: true,
            operatingSystemMajorVersion: 14,
            physicalMemoryBytes: 16 * gib,
            freeDiskBytes: 8_000_000_000,
            model: .compact
        ).isSupported)

        let exactlyEnoughDisk = SystemCompatibility(
            isAppleSilicon: true,
            operatingSystemMajorVersion: 15,
            physicalMemoryBytes: 16 * gib,
            freeDiskBytes: TTSModelOption.quality.estimatedDownloadBytes + 1_000_000_000,
            model: .quality
        )
        #expect(exactlyEnoughDisk.isSupported)
        #expect(exactlyEnoughDisk.hasLowDiskHeadroom)

        let insufficientDisk = SystemCompatibility(
            isAppleSilicon: true,
            operatingSystemMajorVersion: 15,
            physicalMemoryBytes: 16 * gib,
            freeDiskBytes: TTSModelOption.quality.estimatedDownloadBytes + 999_999_999,
            model: .quality
        )
        #expect(!insufficientDisk.isSupported)
    }

    @Test func cacheValidationRequiresEveryNonemptyTTSComponent() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioToText-tts-model-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let config = TTSKitConfig(model: TTSModelOption.compact.variant, modelFolder: folder)
        let components: [(String, String)] = [
            ("text_projector", config.textProjectorVariant),
            ("code_embedder", config.codeEmbedderVariant),
            ("multi_code_embedder", config.multiCodeEmbedderVariant),
            ("code_decoder", config.codeDecoderVariant),
            ("multi_code_decoder", config.multiCodeDecoderVariant),
            ("speech_decoder", config.speechDecoderVariant)
        ]
        var createdFiles: [URL] = []
        for (component, variant) in components {
            let file = folder
                .appendingPathComponent("qwen3_tts/\(component)/\(config.versionDir)/\(variant)")
                .appendingPathComponent("Fixture.mlmodelc/weights/weight.bin")
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([1]).write(to: file)
            createdFiles.append(file)
        }

        #expect(TTSModelOption.isDownloaded(in: folder, model: .compact))
        try Data().write(to: createdFiles.last!)
        let metadata = createdFiles.last!.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("model.mil")
        try Data([1]).write(to: metadata)
        #expect(!TTSModelOption.isDownloaded(in: folder, model: .compact))
    }

    @Test func fullCacheValidationAlsoRequiresTokenizerFiles() throws {
        let modelFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioToText-tts-components-\(UUID().uuidString)", isDirectory: true)
        let tokenizerFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioToText-tts-tokenizer-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: modelFolder)
            try? FileManager.default.removeItem(at: tokenizerFolder)
        }

        let config = TTSKitConfig(model: TTSModelOption.compact.variant, modelFolder: modelFolder)
        let components: [(String, String)] = [
            ("text_projector", config.textProjectorVariant),
            ("code_embedder", config.codeEmbedderVariant),
            ("multi_code_embedder", config.multiCodeEmbedderVariant),
            ("code_decoder", config.codeDecoderVariant),
            ("multi_code_decoder", config.multiCodeDecoderVariant),
            ("speech_decoder", config.speechDecoderVariant)
        ]
        for (component, variant) in components {
            let file = modelFolder
                .appendingPathComponent("qwen3_tts/\(component)/\(config.versionDir)/\(variant)")
                .appendingPathComponent("Fixture.mlmodelc/weights/weight.bin")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: file)
        }

        try FileManager.default.createDirectory(at: tokenizerFolder, withIntermediateDirectories: true)
        for filename in ["tokenizer.json", "tokenizer_config.json", "config.json"] {
            try Data([1]).write(to: tokenizerFolder.appendingPathComponent(filename))
        }
        #expect(TTSModelOption.isDownloaded(in: modelFolder, tokenizerFolder: tokenizerFolder, model: .compact))

        try Data().write(to: tokenizerFolder.appendingPathComponent("tokenizer.json"))
        #expect(!TTSModelOption.isDownloaded(in: modelFolder, tokenizerFolder: tokenizerFolder, model: .compact))
    }

    @Test func generationRequestCarriesSelectedModelLanguageAndVoice() {
        let request = SpeechGenerationRequest(
            text: "Hello",
            model: .quality,
            language: .english,
            voice: .ryan
        )
        #expect(request.text == "Hello")
        #expect(request.model == .quality)
        #expect(request.language == .english)
        #expect(request.voice == .ryan)
    }

    @Test func mp3CommandIsPinnedTo128KbpsMono() {
        let input = URL(fileURLWithPath: "/tmp/input.wav")
        let output = URL(fileURLWithPath: "/tmp/output.mp3")
        #expect(MP3Encoder.commandArguments(input: input, output: output) == [
            "--silent", "-b", "128", "-m", "m", input.path, output.path
        ])
    }

    @Test func releaseInfoPlistDeclaresVersionBuildAndIcon() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repository.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["CFBundleShortVersionString"] as? String == "0.3.3")
        #expect(plist["CFBundleVersion"] as? String == "8")
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
    }
}
