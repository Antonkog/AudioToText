import Foundation
import Testing
@testable import AudioToText

struct MultilingualConfigurationTests {
    @Test func modelCatalogContainsEnglishAndEveryMultilingualSize() {
        #expect(WhisperModelOption.englishModels.map(\.rawValue) == ["tiny.en", "base.en", "small.en"])
        #expect(WhisperModelOption.multilingualModels.map(\.rawValue) == [
            "tiny",
            "base",
            "small",
            "medium",
            "large-v3-v20240930_626MB"
        ])
        #expect(WhisperModelOption.tinyMultilingual.downloadSize == "~76.6 MB")
        #expect(WhisperModelOption.mediumMultilingual.downloadSize == "~1.53 GB")
        #expect(WhisperModelOption.largeV3Multilingual.downloadSize == "~627 MB")
        #expect(!WhisperModelOption.baseEnglish.isMultilingual)
        #expect(WhisperModelOption.baseMultilingual.isMultilingual)
    }

    @Test func englishModelsAlwaysForceEnglish() {
        let options = WhisperEngine.decodingOptions(
            model: .smallEnglish,
            audioLanguage: .language("ja")
        )

        #expect(options.task.description == "transcribe")
        #expect(options.language == "en")
        #expect(options.usePrefillPrompt)
        #expect(!options.detectLanguage)
    }

    @Test func multilingualAutomaticEnablesDetection() {
        let options = WhisperEngine.decodingOptions(
            model: .tinyMultilingual,
            audioLanguage: .automatic
        )

        #expect(options.language == nil)
        #expect(options.usePrefillPrompt)
        #expect(options.detectLanguage)
    }

    @Test func multilingualManualLanguageDisablesDetection() {
        let options = WhisperEngine.decodingOptions(
            model: .largeV3Multilingual,
            audioLanguage: .language("es")
        )

        #expect(options.language == "es")
        #expect(!options.detectLanguage)
    }

    @Test func audioLanguagePreferenceRoundTrips() {
        #expect(AudioLanguageSelection(storedValue: nil) == .automatic)
        #expect(AudioLanguageSelection(storedValue: "automatic") == .automatic)
        #expect(AudioLanguageSelection(storedValue: "ru") == .language("ru"))
        #expect(AudioLanguageSelection.language("pt").storedValue == "pt")
    }

    @Test func audioLanguageCatalogExposesWhispersFullLanguageSet() {
        let codes = Set(AppLocalization.supportedAudioLanguageCodes)
        #expect(codes.count >= 90)
        #expect(["en", "es", "zh", "hi", "ar", "pt", "fr", "de", "ja", "ru"].allSatisfy(codes.contains))
    }

    @Test func everyInterfaceLocalizationHasTheEnglishKeySet() {
        let englishKeys = AppLocalization.localizedKeys(for: .english)
        #expect(!englishKeys.isEmpty)

        for language in AppLanguage.selectableLanguages {
            #expect(
                AppLocalization.localizedKeys(for: language) == englishKeys,
                "Missing or extra localization keys for \(language.rawValue)"
            )
        }
    }

    @Test func localizedFormattingUsesArgumentsAndEnglishFallback() {
        let spanish = AppLocalization.string(
            "status.downloading_model",
            language: .spanish,
            arguments: ["Tiny", "76 MB", "42"]
        )
        #expect(spanish.contains("Tiny"))
        #expect(spanish.contains("42%"))

        let unknownKey = AppLocalization.string("missing.test.key", language: .japanese)
        #expect(unknownKey == "missing.test.key")
    }

    @Test func downloadedModelRequiresEveryNonemptyCoreFile() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioToText-model-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let files = [
            "config.json",
            "AudioEncoder.mlmodelc/weights/weight.bin",
            "MelSpectrogram.mlmodelc/weights/weight.bin",
            "TextDecoder.mlmodelc/weights/weight.bin"
        ]
        for relativePath in files {
            let file = folder.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([1]).write(to: file)
        }

        #expect(WhisperModelOption.isDownloaded(in: folder))
        try Data().write(to: folder.appendingPathComponent(files.last!))
        #expect(!WhisperModelOption.isDownloaded(in: folder))
    }
}
