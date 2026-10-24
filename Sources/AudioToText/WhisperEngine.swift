import Foundation
import WhisperKit

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

    func transcribe(_ url: URL, model: WhisperModelOption) async throws -> String {
        guard let pipeline, loadedModel == model else { throw AppError.modelNotReady }

        let results = try await pipeline.transcribe(audioPath: url.path)
        return TranscriptUtilities.cleaned(results.map(\.text))
    }

    func unload() {
        pipeline = nil
        loadedModel = nil
    }

    func isReady(model: WhisperModelOption) -> Bool {
        pipeline != nil && loadedModel == model
    }
}
