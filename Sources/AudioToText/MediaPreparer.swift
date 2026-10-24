import AVFoundation
import Foundation
import UniformTypeIdentifiers

private final class SendableExportSession: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}

struct PreparedMedia {
    let url: URL
    let isTemporary: Bool

    func removeTemporaryFileIfNeeded() {
        guard isTemporary else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum MediaPreparer {
    @MainActor
    static func prepare(
        _ input: URL,
        onProgress: @escaping (Double) -> Void = { _ in }
    ) async throws -> PreparedMedia {
        let contentType = try? input.resourceValues(forKeys: [.contentTypeKey]).contentType
        let isMovie = contentType?.conforms(to: .movie) == true
            || UTType(filenameExtension: input.pathExtension)?.conforms(to: .movie) == true

        guard isMovie else {
            onProgress(1)
            return PreparedMedia(url: input, isTemporary: false)
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioToText-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let asset = AVURLAsset(url: input)

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw AppError.mediaHasNoAudio }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.mediaHasNoAudio
        }
        let sendableExporter = SendableExportSession(exporter)

        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                onProgress(Double(exporter.progress))
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    break
                }
            }
        }
        defer { progressTask.cancel() }

        do {
            try await withTaskCancellationHandler {
                try await exporter.export(to: output, as: .m4a)
            } onCancel: {
                sendableExporter.value.cancelExport()
            }
            try Task.checkCancellation()
            onProgress(1)
            return PreparedMedia(url: output, isTemporary: true)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
