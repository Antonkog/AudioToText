import Foundation
import TTSKit

enum MP3EncoderError: LocalizedError {
    case executableMissing
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            "The bundled MP3 encoder is unavailable."
        case let .encodingFailed(message):
            "MP3 encoding failed: \(message)"
        }
    }
}

enum MP3Encoder {
    static func commandArguments(input: URL, output: URL) -> [String] {
        ["--silent", "-b", "128", "-m", "m", input.path, output.path]
    }

    static func executableURL(bundle: Bundle = .main) -> URL? {
        let bundled = bundle.resourceURL?
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("lame")
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        for path in ["/opt/homebrew/bin/lame", "/usr/local/bin/lame"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func encode(
        samples: [Float],
        sampleRate: Int,
        destination: URL,
        bundle: Bundle = .main
    ) async throws {
        guard let executable = executableURL(bundle: bundle) else {
            throw MP3EncoderError.executableMissing
        }

        let temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioToText-MP3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryFolder) }

        let wav = try await AudioOutput.saveAudio(
            samples,
            toFolder: temporaryFolder,
            filename: "input",
            sampleRate: sampleRate,
            format: .wav
        )
        try? FileManager.default.removeItem(at: destination)

        let result = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = executable
            process.arguments = commandArguments(input: wav, output: destination)
            process.standardError = errorPipe
            process.standardOutput = Pipe()
            try process.run()
            process.waitUntilExit()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: errorData, encoding: .utf8) ?? "")
        }.value

        guard result.0 == 0, FileManager.default.fileExists(atPath: destination.path) else {
            throw MP3EncoderError.encodingFailed(result.1.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
