import AppKit
import AVFoundation
import Foundation
import TTSKit
import UniformTypeIdentifiers

@MainActor
final class TextToSpeechController: ObservableObject {
    @Published var selectedModel: TTSModelOption {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelDefaultsKey)
            engine.unload()
            isModelReady = false
            selectedModelIsDownloaded = selectedModel.isDownloaded
            compatibility = .current(for: selectedModel)
            invalidateGeneratedAudio()
        }
    }
    @Published var selectedLanguage: TTSSpeechLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Self.languageDefaultsKey)
            invalidateGeneratedAudio()
        }
    }
    @Published var selectedVoice: TTSVoice {
        didSet {
            UserDefaults.standard.set(selectedVoice.rawValue, forKey: Self.voiceDefaultsKey)
            invalidateGeneratedAudio()
        }
    }
    @Published var inputText = "" {
        didSet {
            if inputText != oldValue { invalidateGeneratedAudio() }
        }
    }
    @Published private(set) var statusMessage = LocalizedMessage("tts.status.choose_model")
    @Published private(set) var errorMessageState = LocalizedMessage("error.generic", "")
    @Published private(set) var generatedSpeech: GeneratedSpeech?
    @Published private(set) var selectedModelIsDownloaded: Bool
    @Published private(set) var compatibility: SystemCompatibility
    @Published var isModelReady = false
    @Published var isBusy = false
    @Published var isDownloadingModel = false
    @Published var isGenerating = false
    @Published var isExporting = false
    @Published var modelDownloadProgress = 0.0
    @Published var generationProgress = 0.0
    @Published var isShowingError = false
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published private(set) var savedAudioURL: URL?

    private let engine = TTSEngine()
    private var downloadTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var temporaryAudioFolder: URL?

    private static let modelDefaultsKey = "selectedTTSModel"
    private static let languageDefaultsKey = "selectedTTSLanguage"
    private static let voiceDefaultsKey = "selectedTTSVoice"

    init() {
        let savedModel = TTSModelOption(
            rawValue: UserDefaults.standard.string(forKey: Self.modelDefaultsKey) ?? ""
        ) ?? .compact
        selectedModel = savedModel
        selectedLanguage = TTSSpeechLanguage(
            rawValue: UserDefaults.standard.string(forKey: Self.languageDefaultsKey) ?? ""
        ) ?? .english
        selectedVoice = TTSVoice(
            rawValue: UserDefaults.standard.string(forKey: Self.voiceDefaultsKey) ?? ""
        ) ?? .ryan
        selectedModelIsDownloaded = savedModel.isDownloaded
        compatibility = .current(for: savedModel)
        if savedModel.isDownloaded {
            statusMessage = LocalizedMessage("tts.status.downloaded")
        }
    }

    var hasGeneratedAudio: Bool { generatedSpeech != nil }
    var canGenerate: Bool {
        isModelReady && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    func activate() {
        compatibility = .current(for: selectedModel)
        selectedModelIsDownloaded = selectedModel.isDownloaded
        if selectedModelIsDownloaded, !isModelReady, !isBusy {
            loadSelectedModel()
        }
    }

    func deactivate() {
        stopPlayback()
        engine.unload()
        isModelReady = false
        if selectedModelIsDownloaded {
            statusMessage = LocalizedMessage("tts.status.downloaded")
        }
    }

    func selectModel(_ model: TTSModelOption) {
        guard !isBusy, model != selectedModel else { return }
        selectedModel = model
        statusMessage = model.isDownloaded
            ? LocalizedMessage("tts.status.loading_model")
            : LocalizedMessage("tts.status.choose_model")
        if selectedModelIsDownloaded { loadSelectedModel() }
    }

    func refreshCompatibility() {
        compatibility = .current(for: selectedModel)
    }

    func downloadSelectedModel() {
        guard !isBusy, !selectedModelIsDownloaded, compatibility.isSupported else { return }
        let model = selectedModel
        downloadTask = Task { [weak self] in
            guard let self else { return }
            isBusy = true
            isDownloadingModel = true
            modelDownloadProgress = 0
            statusMessage = LocalizedMessage("tts.status.downloading", model.downloadSize, "0")
            do {
                try await engine.downloadAndPrepare(model: model) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.selectedModel == model else { return }
                        self.modelDownloadProgress = max(self.modelDownloadProgress, fraction)
                        guard fraction < 1 else { return }
                        if fraction < 0.75 {
                            self.statusMessage = LocalizedMessage(
                                "tts.status.downloading",
                                model.downloadSize,
                                String(Int(fraction * 100))
                            )
                        } else {
                            self.statusMessage = LocalizedMessage(
                                "tts.status.preparing",
                                String(Int(fraction * 100))
                            )
                        }
                    }
                }
                guard selectedModel == model else { return }
                selectedModelIsDownloaded = true
                isModelReady = true
                modelDownloadProgress = 1
                statusMessage = LocalizedMessage("tts.status.ready")
            } catch is CancellationError {
                modelDownloadProgress = 0
                selectedModelIsDownloaded = model.isDownloaded
                isModelReady = false
                statusMessage = LocalizedMessage("tts.status.download_cancelled")
            } catch {
                isModelReady = false
                show(error)
            }
            isDownloadingModel = false
            isBusy = false
            downloadTask = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func openModelInFinder() {
        guard let folder = TTSModelOption.localRepositoryFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func generate() {
        guard canGenerate else {
            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                show(TTSAppError.emptyText)
            }
            return
        }
        let request = SpeechGenerationRequest(
            text: inputText.trimmingCharacters(in: .whitespacesAndNewlines),
            model: selectedModel,
            language: selectedLanguage,
            voice: selectedVoice
        )
        generationTask = Task { [weak self] in
            guard let self else { return }
            stopPlayback()
            clearTemporaryAudio()
            generatedSpeech = nil
            savedAudioURL = nil
            generationProgress = 0
            isBusy = true
            isGenerating = true
            statusMessage = LocalizedMessage("tts.status.generating", "0")
            do {
                let output = try await engine.generate(request: request) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self else { return }
                        self.generationProgress = max(self.generationProgress, fraction)
                        guard fraction < 1 else { return }
                        self.statusMessage = LocalizedMessage("tts.status.generating", String(Int(fraction * 100)))
                    }
                    return !Task.isCancelled
                }
                try Task.checkCancellation()
                generatedSpeech = output
                generationProgress = 1
                try await preparePlaybackFile(output)
                statusMessage = LocalizedMessage("tts.status.generated", Self.durationString(output.duration))
            } catch is CancellationError {
                generationProgress = 0
                statusMessage = LocalizedMessage("tts.status.generation_cancelled")
            } catch {
                show(error)
            }
            isGenerating = false
            isBusy = false
            generationTask = nil
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
    }

    func play() {
        guard let url = temporaryAudioURL else { return }
        do {
            if let player = audioPlayer, isPaused {
                player.play()
            } else {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                player.play()
                audioPlayer = player
            }
            isPlaying = true
            isPaused = false
            startPlaybackTimer()
        } catch {
            show(error)
        }
    }

    func pausePlayback() {
        guard audioPlayer?.isPlaying == true else { return }
        audioPlayer?.pause()
        isPlaying = false
        isPaused = true
        playbackTimer?.invalidate()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioPlayer = nil
        isPlaying = false
        isPaused = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func saveM4A(title: String, prompt: String) {
        chooseDestinationAndSave(format: .m4a, title: title, prompt: prompt)
    }

    func saveMP3(title: String, prompt: String) {
        chooseDestinationAndSave(format: .mp3, title: title, prompt: prompt)
    }

    func revealSavedAudioInFinder() {
        guard let savedAudioURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedAudioURL])
    }

    private func loadSelectedModel() {
        guard !isBusy, selectedModelIsDownloaded else { return }
        let model = selectedModel
        isBusy = true
        statusMessage = LocalizedMessage("tts.status.loading_model")
        Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.loadDownloaded(model: model)
                guard selectedModel == model else { return }
                isModelReady = true
                statusMessage = LocalizedMessage("tts.status.ready")
            } catch {
                isModelReady = false
                show(error)
            }
            isBusy = false
        }
    }

    private func chooseDestinationAndSave(format: TTSExportFormat, title: String, prompt: String) {
        guard let output = generatedSpeech, !isBusy else { return }
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = prompt
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .audio]
        panel.nameFieldStringValue = "AudioToText-\(Self.filenameTimestamp()).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task { [weak self] in
            guard let self else { return }
            isBusy = true
            isExporting = true
            statusMessage = LocalizedMessage("tts.status.saving")
            do {
                let finalURL: URL
                switch format {
                case .m4a:
                    finalURL = try await AudioOutput.saveAudio(
                        output.samples,
                        toFolder: url.deletingLastPathComponent(),
                        filename: url.lastPathComponent,
                        sampleRate: output.sampleRate,
                        format: .m4a
                    )
                case .mp3:
                    finalURL = url.deletingPathExtension().appendingPathExtension("mp3")
                    try await MP3Encoder.encode(
                        samples: output.samples,
                        sampleRate: output.sampleRate,
                        destination: finalURL
                    )
                }
                savedAudioURL = finalURL
                statusMessage = LocalizedMessage("tts.status.saved", finalURL.lastPathComponent)
            } catch {
                show(error)
            }
            isExporting = false
            isBusy = false
        }
    }

    private var temporaryAudioURL: URL? {
        temporaryAudioFolder?.appendingPathComponent("preview.m4a")
    }

    private func preparePlaybackFile(_ output: GeneratedSpeech) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioToText-TTS-\(UUID().uuidString)", isDirectory: true)
        temporaryAudioFolder = folder
        _ = try await AudioOutput.saveAudio(
            output.samples,
            toFolder: folder,
            filename: "preview",
            sampleRate: output.sampleRate,
            format: .m4a
        )
    }

    private func invalidateGeneratedAudio() {
        guard generatedSpeech != nil || temporaryAudioFolder != nil else { return }
        stopPlayback()
        generatedSpeech = nil
        savedAudioURL = nil
        generationProgress = 0
        clearTemporaryAudio()
    }

    private func clearTemporaryAudio() {
        if let temporaryAudioFolder { try? FileManager.default.removeItem(at: temporaryAudioFolder) }
        temporaryAudioFolder = nil
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if self.audioPlayer?.isPlaying != true {
                    timer.invalidate()
                    self.isPlaying = false
                    self.isPaused = false
                    self.audioPlayer = nil
                }
            }
        }
    }

    private func show(_ error: Error) {
        let key: String
        switch error {
        case TTSAppError.emptyText: key = "tts.error.empty_text"
        case MP3EncoderError.executableMissing: key = "tts.error.mp3_unavailable"
        default: key = "error.generic"
        }
        errorMessageState = key == "error.generic"
            ? LocalizedMessage(key, error.localizedDescription)
            : LocalizedMessage(key)
        statusMessage = errorMessageState
        isShowingError = true
    }

    private static func durationString(_ duration: Double) -> String {
        String(format: "%.1f", duration)
    }

    private static func filenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}

enum TTSExportFormat { case m4a, mp3
    var fileExtension: String { self == .m4a ? "m4a" : "mp3" }
}

enum TTSAppError: Error { case emptyText }
