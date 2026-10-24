import Foundation
import WhisperKit

struct TranscriptionOutput: Equatable {
    let text: String
    let languageCode: String?
}

@MainActor
final class WhisperEngine {
    private var pipeline: WhisperKit?
    private var loadedModel: WhisperModelOption?

    func downloadAndPrepare(
        model: WhisperModelOption,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard pipeline == nil || loadedModel != model else { return }

        pipeline = nil
        loadedModel = nil

        let modelFolder = try await WhisperKit.download(
            variant: model.rawValue,
            progressCallback: { progress in
                onProgress(progress.fractionCompleted)
            }
        )
        onProgress(1)

        try await loadPipeline(from: modelFolder, model: model)
    }

    func loadDownloaded(model: WhisperModelOption) async throws {
        guard let modelFolder = model.localFolder, model.isDownloaded else {
            throw AppError.modelNotReady
        }

        pipeline = nil
        loadedModel = nil
        try await loadPipeline(from: modelFolder, model: model)
    }

    private func loadPipeline(from modelFolder: URL, model: WhisperModelOption) async throws {

        let instance = try await WhisperKit(
            modelFolder: modelFolder.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        pipeline = instance
        loadedModel = model
    }

    func transcribe(
        _ url: URL,
        model: WhisperModelOption,
        audioLanguage: AudioLanguageSelection,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionOutput {
        guard let pipeline, loadedModel == model else { throw AppError.modelNotReady }

        onProgress(0)
        let results = try await pipeline.transcribe(
            audioPath: url.path,
            decodeOptions: Self.decodingOptions(model: model, audioLanguage: audioLanguage),
            callback: { _ in
                onProgress(pipeline.progress.fractionCompleted)
                return !Task.isCancelled
            }
        )
        try Task.checkCancellation()
        onProgress(1)
        let text = TranscriptUtilities.cleaned(results.map(\.text))
        let languageCode = results.lazy.map(\.language).first(where: { !$0.isEmpty })
        return TranscriptionOutput(text: text, languageCode: languageCode)
    }

    nonisolated static func decodingOptions(
        model: WhisperModelOption,
        audioLanguage: AudioLanguageSelection
    ) -> DecodingOptions {
        guard model.isMultilingual else {
            return DecodingOptions(
                task: .transcribe,
                language: "en",
                usePrefillPrompt: true,
                detectLanguage: false
            )
        }

        switch audioLanguage {
        case .automatic:
            return DecodingOptions(
                task: .transcribe,
                language: nil,
                usePrefillPrompt: true,
                detectLanguage: true
            )
        case let .language(code):
            return DecodingOptions(
                task: .transcribe,
                language: code,
                usePrefillPrompt: true,
                detectLanguage: false
            )
        }
    }

    func unload() {
        pipeline = nil
        loadedModel = nil
    }

    func isReady(model: WhisperModelOption) -> Bool {
        pipeline != nil && loadedModel == model
    }
}
