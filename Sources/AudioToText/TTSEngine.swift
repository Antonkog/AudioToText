import Foundation
import TTSKit

@MainActor
final class TTSEngine {
    private var kit: TTSKit?
    private var loadedModel: TTSModelOption?

    func downloadAndPrepare(
        model: TTSModelOption,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        unload()
        try Task.checkCancellation()
        try removeIncompleteModelCache(for: model)
        var completed = false
        defer {
            if !completed { try? removeIncompleteModelCache(for: model) }
        }

        let config = TTSKitConfig(
            model: model.variant,
            modelRepo: ModelRepositories.textToSpeech,
            verbose: false
        )
        let folder: URL
        do {
            folder = try await TTSKit.download(config: config) { progress in
                onProgress(min(0.7, progress.fractionCompleted * 0.7))
            }
        } catch {
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()
        guard TTSModelOption.isDownloaded(in: folder, model: model) else {
            throw TTSError.modelNotFound(folder.path)
        }

        let tokenizerFolder = try await prepareTokenizer { progress in
            onProgress(0.7 + (progress * 0.05))
        }
        let instance = try await makeKit(
            model: model,
            folder: folder,
            tokenizerFolder: tokenizerFolder
        )
        onProgress(0.78)
        let estimatedPrewarmProgress = Task {
            var fraction = 0.78
            while !Task.isCancelled, fraction < 0.895 {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                fraction = min(0.895, fraction + 0.003)
                onProgress(fraction)
            }
        }
        defer { estimatedPrewarmProgress.cancel() }
        do {
            try await instance.prewarmModels()
        } catch {
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()
        onProgress(0.9)
        do {
            try await instance.loadModels()
        } catch {
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()

        guard model.isDownloaded else {
            throw TTSError.modelNotFound("The model or its tokenizer cache is incomplete")
        }

        kit = instance
        loadedModel = model
        completed = true
        _ = onProgress(1)
    }

    func loadDownloaded(model: TTSModelOption) async throws {
        guard let folder = TTSModelOption.downloadedRepositoryFolder(for: model), model.isDownloaded else {
            throw TTSError.modelNotFound(model.rawValue)
        }
        unload()
        let instance = try await makeKit(
            model: model,
            folder: folder,
            tokenizerFolder: TTSModelOption.downloadedTokenizerFolder
        )
        try await instance.loadModels()
        try Task.checkCancellation()
        kit = instance
        loadedModel = model
    }

    func generate(
        request: SpeechGenerationRequest,
        onProgress: @escaping @Sendable (Double) -> Bool
    ) async throws -> GeneratedSpeech {
        guard let kit, loadedModel == request.model else {
            throw TTSError.modelLoadingFailed("The selected TTS model is not loaded")
        }
        let result = try await kit.generate(
            text: request.text,
            voice: request.voice.rawValue,
            language: request.language.rawValue,
            options: GenerationOptions(concurrentWorkerCount: 1),
            callback: { progress in
                guard !Task.isCancelled else { return false }
                let completed = Double(progress.stepsCompleted ?? 0)
                let total = Double(max(1, progress.totalSteps ?? 1))
                return onProgress(min(0.99, completed / total))
            }
        )
        try Task.checkCancellation()
        _ = onProgress(1)
        return GeneratedSpeech(
            samples: result.audio,
            sampleRate: result.sampleRate,
            duration: result.audioDuration,
            request: request
        )
    }

    func unload() {
        let previous = kit
        kit = nil
        loadedModel = nil
        Task { await previous?.unloadModels() }
    }

    func isReady(model: TTSModelOption) -> Bool {
        kit != nil && loadedModel == model
    }

    private func makeKit(
        model: TTSModelOption,
        folder: URL,
        tokenizerFolder: URL?
    ) async throws -> TTSKit {
        let config = TTSKitConfig(
            model: model.variant,
            modelFolder: folder,
            modelRepo: ModelRepositories.textToSpeech,
            tokenizerFolder: tokenizerFolder,
            speechDecoderMode: .throughputOptimized,
            verbose: false
        )
        config.download = false
        config.load = false
        return try await TTSKit(config)
    }

    private func prepareTokenizer(
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        if let folder = TTSModelOption.downloadedTokenizerFolder {
            onProgress(1)
            return folder
        }
        guard let folder = TTSModelOption.localTokenizerFolder else {
            throw TTSError.tokenizerUnavailable("The tokenizer cache folder is unavailable")
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let total = Double(ModelRepositories.tokenizerFiles.count)

        for (index, filename) in ModelRepositories.tokenizerFiles.enumerated() {
            try Task.checkCancellation()
            guard let remoteURL = ModelRepositories.downloadURL(
                repository: ModelRepositories.tokenizer,
                filename: filename
            ) else {
                throw TTSError.tokenizerUnavailable("The tokenizer download URL is invalid")
            }

            let destination = folder.appendingPathComponent(filename)
            let (temporaryFile, response) = try await URLSession.shared.download(from: remoteURL)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw TTSError.tokenizerUnavailable("Failed to download \(filename)")
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporaryFile, to: destination)
            onProgress(Double(index + 1) / total)
        }

        guard TTSModelOption.isTokenizerDownloaded(in: folder) else {
            throw TTSError.tokenizerUnavailable("The downloaded tokenizer cache is incomplete")
        }
        return folder
    }

    private func removeIncompleteModelCache(for model: TTSModelOption) throws {
        guard
            let folder = TTSModelOption.localRepositoryFolder,
            FileManager.default.fileExists(atPath: folder.path),
            !TTSModelOption.isDownloaded(in: folder, model: model)
        else { return }

        let config = TTSKitConfig(model: model.variant, modelFolder: folder)
        for componentDirectory in config.componentDirectories(in: folder)
        where FileManager.default.fileExists(atPath: componentDirectory.path) {
            try FileManager.default.removeItem(at: componentDirectory)
        }
    }
}
