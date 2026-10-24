import AppKit
import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum AudioSource: String, CaseIterable, Identifiable {
    case file
    case systemAudio
    case microphone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file: "File"
        case .systemAudio: "Mac Audio"
        case .microphone: "Microphone"
        }
    }

    var symbol: String {
        switch self {
        case .file: "waveform.badge.plus"
        case .systemAudio: "play.rectangle.on.rectangle"
        case .microphone: "mic.fill"
        }
    }

    var headline: String {
        switch self {
        case .file: "Transcribe an audio or video file"
        case .systemAudio: "Capture sound playing on this Mac"
        case .microphone: "Record speech from your microphone"
        }
    }

    var instructions: String {
        switch self {
        case .file:
            "Choose a recording, podcast, voice note, or movie. You can also drag a file anywhere into this window."
        case .systemAudio:
            "Start recording, then play a movie, YouTube video, meeting, or any other app. Stop when you want the transcript; recording ends automatically after 2 hours."
        case .microphone:
            "Useful for dictation, interviews, and in-person conversations. Stop to transcribe; recording ends automatically after 2 hours."
        }
    }
}

enum WhisperModelOption: String, CaseIterable, Identifiable {
    case tinyEnglish = "tiny.en"
    case baseEnglish = "base.en"
    case smallEnglish = "small.en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tinyEnglish: "Tiny English"
        case .baseEnglish: "Base English"
        case .smallEnglish: "Small English"
        }
    }

    var detail: String {
        switch self {
        case .tinyEnglish: "Fastest · ~153 MB"
        case .baseEnglish: "Balanced · ~147 MB"
        case .smallEnglish: "Most accurate · ~487 MB"
        }
    }

    var downloadSize: String {
        switch self {
        case .tinyEnglish: "~153 MB"
        case .baseEnglish: "~147 MB"
        case .smallEnglish: "~487 MB"
        }
    }

    var localFolder: URL? {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }

        return documents
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(rawValue)", isDirectory: true)
    }

    var isDownloaded: Bool {
        guard let localFolder else { return false }
        let requiredFiles = [
            "config.json",
            "AudioEncoder.mlmodelc/weights/weight.bin",
            "MelSpectrogram.mlmodelc/weights/weight.bin",
            "TextDecoder.mlmodelc/weights/weight.bin"
        ]
        return requiredFiles.allSatisfy { relativePath in
            let file = localFolder.appendingPathComponent(relativePath)
            guard
                FileManager.default.fileExists(atPath: file.path),
                let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return false }
            return size > 0
        }
    }
}

@MainActor
final class TranscriptionController: ObservableObject {
    @Published var source: AudioSource = .file
    @Published var selectedModel: WhisperModelOption {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelDefaultsKey)
            whisper.unload()
            isModelReady = false
            selectedModelIsDownloaded = selectedModel.isDownloaded
            isDownloadingModel = false
            modelDownloadProgress = 0
            if !isBusy {
                status = selectedModelIsDownloaded
                    ? "Loading \(selectedModel.title) from disk…"
                    : "Choose a source to begin"
            }
        }
    }
    @Published var transcript = "" {
        didSet {
            guard !isApplyingTranscript, let savedTranscriptURL else { return }
            try? transcript.write(to: savedTranscriptURL, atomically: true, encoding: .utf8)
        }
    }
    @Published var status = "Choose a source to begin"
    @Published var selectedFile: URL?
    @Published var savedTranscriptURL: URL?
    @Published var isBusy = false
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var transcriptionProgress = 0.0
    @Published var isModelReady = false
    @Published var selectedModelIsDownloaded: Bool
    @Published var isDownloadingModel = false
    @Published var modelDownloadProgress = 0.0
    @Published var isShowingImporter = false
    @Published var isDropTargeted = false
    @Published var isShowingError = false
    @Published var errorMessage = ""
    @Published var errorNeedsScreenRecordingPermission = false
    @Published var statusIsError = false
    @Published var audioLevel: CGFloat = 0.02
    @Published var recordingSeconds = 0

    private let whisper = WhisperEngine()
    private var microphoneRecorder: MicrophoneRecorder?
    private var systemRecorder: SystemAudioRecorder?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var transcriptionTask: Task<Void, Never>?
    private var isApplyingTranscript = false
    private static let modelDefaultsKey = "selectedWhisperModel"
    private static let maximumRecordingSeconds = 2 * 60 * 60

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.modelDefaultsKey)
        let model = WhisperModelOption(rawValue: saved ?? "") ?? .baseEnglish
        selectedModel = model
        selectedModelIsDownloaded = model.isDownloaded

        if model.isDownloaded {
            Task { [weak self] in
                self?.loadSelectedModelFromDisk()
            }
        }
    }

    var statusSymbol: String {
        if statusIsError { return "exclamationmark.triangle.fill" }
        if savedTranscriptURL != nil { return "checkmark.circle.fill" }
        return "lock.shield.fill"
    }

    var recordingDurationText: String {
        String(format: "%02d:%02d", recordingSeconds / 60, recordingSeconds % 60)
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            selectFile(url)
        case let .failure(error):
            show(error)
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSURL.self) }) else {
            return false
        }

        _ = provider.loadObject(ofClass: NSURL.self) { [weak self] object, _ in
            guard let url = object as? URL else { return }
            Task { @MainActor in
                self?.selectFile(url)
            }
        }
        return true
    }

    func selectFile(_ url: URL) {
        selectedFile = url
        source = .file
        savedTranscriptURL = nil
        statusIsError = false
        status = "Ready to transcribe \(url.lastPathComponent)"
    }

    func selectModel(_ model: WhisperModelOption) {
        guard !isBusy else { return }
        guard selectedModel != model else { return }
        selectedModel = model
        if selectedModelIsDownloaded {
            loadSelectedModelFromDisk()
        }
    }

    func performModelAction() {
        downloadSelectedModel()
    }

    func openSelectedModelInFinder() {
        guard let folder = selectedModel.localFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func revealSavedTranscriptInFinder() {
        guard let savedTranscriptURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedTranscriptURL])
    }

    private func downloadSelectedModel() {
        guard !isBusy, !selectedModelIsDownloaded else { return }

        let model = selectedModel
        Task {
            do {
                statusIsError = false
                isBusy = true
                isDownloadingModel = true
                modelDownloadProgress = 0
                status = selectedModelIsDownloaded
                    ? "Loading \(model.title)…"
                    : "Downloading \(model.title) (\(model.downloadSize))… 0%"

                try await whisper.downloadAndPrepare(model: model) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.selectedModel == model else { return }
                        let clamped = min(1, max(self.modelDownloadProgress, fraction))
                        self.modelDownloadProgress = clamped
                        self.status = "Downloading \(model.title) (\(model.downloadSize))… \(Int(clamped * 100))%"
                    }
                }

                modelDownloadProgress = 1
                selectedModelIsDownloaded = true
                isModelReady = true
                status = "\(model.title) is ready for offline use"
            } catch {
                isModelReady = false
                show(error)
            }
            isDownloadingModel = false
            isBusy = false
        }
    }

    private func loadSelectedModelFromDisk() {
        guard !isBusy, selectedModelIsDownloaded else { return }

        let model = selectedModel
        isBusy = true
        statusIsError = false
        status = "Loading \(model.title) from disk…"

        Task {
            do {
                try await whisper.loadDownloaded(model: model)
                guard selectedModel == model else { return }
                isModelReady = true
                status = "Choose a source to begin"
            } catch {
                isModelReady = false
                show(error)
            }
            isBusy = false
        }
    }

    var shouldShowStatusRow: Bool {
        isBusy || isRecording || statusIsError || selectedFile != nil || savedTranscriptURL != nil
    }

    func transcribeSelectedFile() {
        guard let selectedFile else {
            isShowingImporter = true
            return
        }
        guard !isBusy else { return }

        beginTranscription(
            url: selectedFile,
            suggestedName: selectedFile.deletingPathExtension().lastPathComponent
        )
    }

    func chooseAnotherFile() {
        guard !isBusy else { return }
        isShowingImporter = true
    }

    func cancelTranscription() {
        guard isTranscribing else { return }
        statusIsError = false
        status = "Cancelling transcription…"
        transcriptionTask?.cancel()
    }

    func startRecording() {
        guard !isBusy else { return }

        Task {
            do {
                resetForWork()
                isBusy = true
                recordingSeconds = 0
                audioLevel = 0.02

                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("AudioToText-\(UUID().uuidString)")
                    .appendingPathExtension("wav")
                recordingURL = url

                let levelHandler: (CGFloat) -> Void = { [weak self] level in
                    Task { @MainActor in
                        self?.audioLevel = max(0.02, min(1, level))
                    }
                }

                switch source {
                case .microphone:
                    try await ensureMicrophonePermission()

                    let recorder = MicrophoneRecorder()
                    try recorder.start(writingTo: url, onLevel: levelHandler)
                    microphoneRecorder = recorder
                    status = "Recording microphone…"

                case .systemAudio:
                    let recorder = SystemAudioRecorder()
                    recorder.onFailure = { [weak self] error in
                        Task { @MainActor in
                            self?.recordingFailed(error)
                        }
                    }
                    try await recorder.start(writingTo: url, onLevel: levelHandler)
                    systemRecorder = recorder
                    status = "Recording Mac audio… play your source now"

                case .file:
                    throw AppError.invalidSource
                }

                isRecording = true
                startTimer()
            } catch {
                cleanUpRecording()
                isBusy = false
                show(error)
            }
        }
    }

    func stopRecording() {
        guard isRecording, let recordingURL else { return }

        isRecording = false
        stopTimer()
        status = "Finishing recording…"

        let microphoneRecorder = microphoneRecorder
        let systemRecorder = systemRecorder
        self.microphoneRecorder = nil
        self.systemRecorder = nil
        let sourceName = source == .microphone ? "Microphone" : "Mac Audio"

        beginTranscription(
            url: recordingURL,
            suggestedName: sourceName,
            removeInputWhenFinished: true
        ) {
            microphoneRecorder?.stop()
            await systemRecorder?.stop()
        }
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        status = "Transcript copied"
    }

    func saveTranscriptAs() {
        guard !transcript.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = savedTranscriptURL?.lastPathComponent ?? "Transcript.txt"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try transcript.write(to: url, atomically: true, encoding: .utf8)
            savedTranscriptURL = url
            statusIsError = false
            status = "Saved \(url.lastPathComponent)"
        } catch {
            show(error)
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func transcribe(url: URL, suggestedName: String) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            resetForWork()
            isBusy = true
            try Task.checkCancellation()

            guard isModelReady, whisper.isReady(model: selectedModel) else {
                throw AppError.modelNotReady
            }

            status = "Preparing audio…"
            let prepared = try await MediaPreparer.prepare(url) { [weak self] fraction in
                guard let self, self.isTranscribing else { return }
                self.transcriptionProgress = max(
                    self.transcriptionProgress,
                    min(0.1, fraction * 0.1)
                )
            }
            defer { prepared.removeTemporaryFileIfNeeded() }

            status = "Transcribing locally with Whisper…"
            let text = try await whisper.transcribe(
                prepared.url,
                model: selectedModel
            ) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, self.isTranscribing else { return }
                    self.transcriptionProgress = max(
                        self.transcriptionProgress,
                        min(0.99, 0.1 + fraction * 0.9)
                    )
                }
            }

            guard !text.isEmpty else { throw AppError.noSpeechFound }
            applyTranscript(text)

            let output = try TranscriptStore.save(text, suggestedName: suggestedName)
            savedTranscriptURL = output
            transcriptionProgress = 1
            status = "Done — saved \(output.lastPathComponent)"
            statusIsError = false
        } catch is CancellationError {
            transcriptionProgress = 0
            statusIsError = false
            status = "Transcription cancelled"
        } catch {
            show(error)
        }

        isBusy = false
    }

    private func beginTranscription(
        url: URL,
        suggestedName: String,
        removeInputWhenFinished: Bool = false,
        beforeTranscription: (@MainActor () async -> Void)? = nil
    ) {
        guard transcriptionTask == nil else { return }

        isBusy = true
        isTranscribing = true
        transcriptionProgress = 0
        statusIsError = false
        status = beforeTranscription == nil ? "Preparing audio…" : "Finishing recording…"

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if removeInputWhenFinished {
                    try? FileManager.default.removeItem(at: url)
                    if self.recordingURL == url {
                        self.recordingURL = nil
                    }
                }
                self.isTranscribing = false
                self.isBusy = false
                self.transcriptionTask = nil
            }

            if let beforeTranscription {
                await beforeTranscription()
            }

            guard !Task.isCancelled else {
                self.markTranscriptionCancelled()
                return
            }

            await self.transcribe(url: url, suggestedName: suggestedName)
        }
    }

    private func markTranscriptionCancelled() {
        transcriptionProgress = 0
        statusIsError = false
        status = "Transcription cancelled"
    }

    private func applyTranscript(_ value: String) {
        isApplyingTranscript = true
        transcript = value
        isApplyingTranscript = false
    }

    private func resetForWork() {
        statusIsError = false
        savedTranscriptURL = nil
    }

    private func startTimer() {
        stopTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recordingSeconds += 1
                if self.recordingSeconds >= Self.maximumRecordingSeconds {
                    self.stopRecording()
                }
            }
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func recordingFailed(_ error: Error) {
        guard isRecording else { return }
        cleanUpRecording()
        isBusy = false
        show(error)
    }

    private func cleanUpRecording() {
        microphoneRecorder?.stop()
        microphoneRecorder = nil
        if let systemRecorder {
            Task { await systemRecorder.stop() }
        }
        systemRecorder = nil
        isRecording = false
        stopTimer()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }

    private func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw AppError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw AppError.microphonePermissionDenied
        @unknown default:
            throw AppError.microphonePermissionDenied
        }
    }

    private func show(_ error: Error) {
        statusIsError = true
        status = error.localizedDescription
        errorMessage = error.localizedDescription
        errorNeedsScreenRecordingPermission = (error as? AppError) == .screenRecordingPermissionDenied
        isShowingError = true
    }
}

enum AppError: LocalizedError, Equatable {
    case invalidSource
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case noDisplayFound
    case noSpeechFound
    case modelUnavailable
    case modelNotReady
    case mediaHasNoAudio

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            "Choose Mac Audio or Microphone before recording."
        case .microphonePermissionDenied:
            "Microphone access is off. Enable AudioToText in System Settings → Privacy & Security → Microphone."
        case .screenRecordingPermissionDenied:
            "Mac audio capture needs Screen Recording access. Enable AudioToText in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app."
        case .noDisplayFound:
            "No display is available for Mac audio capture."
        case .noSpeechFound:
            "Whisper did not find English speech in this recording."
        case .modelUnavailable:
            "The Whisper model could not be loaded. Check your connection for the first download and try again."
        case .modelNotReady:
            "Download the selected Whisper model before transcribing. Downloaded models load automatically when selected."
        case .mediaHasNoAudio:
            "This file does not contain an audio track that can be transcribed."
        }
    }
}
