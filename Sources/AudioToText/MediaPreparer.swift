import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct PreparedMedia {
    let url: URL
    let isTemporary: Bool

    func removeTemporaryFileIfNeeded() {
        guard isTemporary else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum MediaPreparer {
    static func prepare(_ input: URL) async throws -> PreparedMedia {
        let contentType = try? input.resourceValues(forKeys: [.contentTypeKey]).contentType
        let isMovie = contentType?.conforms(to: .movie) == true
            || UTType(filenameExtension: input.pathExtension)?.conforms(to: .movie) == true

        guard isMovie else {
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

        try await exporter.export(to: output, as: .m4a)
        return PreparedMedia(url: output, isTemporary: true)
    }
}
