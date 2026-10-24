import AVFoundation
import CoreGraphics
import Foundation

final class MicrophoneRecorder {
    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?

    func start(writingTo url: URL, onLevel: @escaping (CGFloat) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AppError.mediaHasNoAudio
        }

        outputFile = try AVAudioFile(forWriting: url, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.outputFile?.write(from: buffer)
            onLevel(AudioLevel.normalizedPower(from: buffer))
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        guard engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        outputFile = nil
    }
}

enum AudioLevel {
    static func normalizedPower(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0.02 }

        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for index in 0..<count {
                let sample = samples[index]
                sum += sample * sample
            }
        }

        let divisor = Float(max(1, count * Int(buffer.format.channelCount)))
        let rms = sqrt(sum / divisor)
        let decibels = 20 * log10(max(rms, 0.000_001))
        return CGFloat(max(0.02, min(1, (decibels + 55) / 55)))
    }
}
