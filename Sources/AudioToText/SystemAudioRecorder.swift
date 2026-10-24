import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onFailure: ((Error) -> Void)?

    private let audioQueue = DispatchQueue(label: "AudioToText.system-audio")
    private var stream: SCStream?
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var onLevel: ((CGFloat) -> Void)?
    private var stopping = false

    func start(writingTo url: URL, onLevel: @escaping (CGFloat) -> Void) async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw AppError.screenRecordingPermissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else { throw AppError.noDisplayFound }

        let currentBundleID = Bundle.main.bundleIdentifier
        let excludedApps = content.applications.filter { application in
            application.bundleIdentifier == currentBundleID
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.queueDepth = 3

        self.outputURL = url
        self.onLevel = onLevel
        stopping = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() async {
        stopping = true
        if let stream {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .audio)
        }
        self.stream = nil
        audioQueue.sync {
            self.outputFile = nil
            self.outputURL = nil
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid, !stopping else { return }

        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard
                    let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                    let format = AVAudioFormat(
                        standardFormatWithSampleRate: description.mSampleRate,
                        channels: description.mChannelsPerFrame
                    ),
                    let samples = AVAudioPCMBuffer(
                        pcmFormat: format,
                        bufferListNoCopy: audioBufferList.unsafePointer
                    )
                else { return }

                if outputFile == nil, let outputURL {
                    outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
                }
                try outputFile?.write(from: samples)
                onLevel?(AudioLevel.normalizedPower(from: samples))
            }
        } catch {
            onFailure?(error)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !stopping else { return }
        onFailure?(error)
    }
}
