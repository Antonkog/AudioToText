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

    var titleKey: String {
        switch self {
        case .file: "source.file"
        case .systemAudio: "source.mac_audio"
        case .microphone: "source.microphone"
        }
    }

    var symbol: String {
        switch self {
        case .file: "waveform.badge.plus"
        case .systemAudio: "play.rectangle.on.rectangle"
        case .microphone: "mic.fill"
        }
    }

    var headlineKey: String {
        switch self {
        case .file: "source.file.headline"
        case .systemAudio: "source.mac_audio.headline"
        case .microphone: "source.microphone.headline"
        }
    }

    var instructionsKey: String {
        switch self {
        case .file:
            "source.file.instructions"
        case .systemAudio:
            "source.mac_audio.instructions"
        case .microphone:
            "source.microphone.instructions"
        }
    }
}

enum WhisperModelOption: String, CaseIterable, Identifiable {
    case tinyEnglish = "tiny.en"
    case baseEnglish = "base.en"
    case smallEnglish = "small.en"
    case tinyMultilingual = "tiny"
    case baseMultilingual = "base"
    case smallMultilingual = "small"
    case mediumMultilingual = "medium"
    case largeV3Multilingual = "large-v3-v20240930_626MB"

    var id: String { rawValue }

    static let englishModels: [WhisperModelOption] = [.tinyEnglish, .baseEnglish, .smallEnglish]
    static let multilingualModels: [WhisperModelOption] = [
        .tinyMultilingual,
        .baseMultilingual,
        .smallMultilingual,
        .mediumMultilingual,
        .largeV3Multilingual
    ]

    var titleKey: String {
        switch self {
        case .tinyEnglish: "model.tiny_english"
        case .baseEnglish: "model.base_english"
        case .smallEnglish: "model.small_english"
        case .tinyMultilingual: "model.tiny_multilingual"
        case .baseMultilingual: "model.base_multilingual"
        case .smallMultilingual: "model.small_multilingual"
        case .mediumMultilingual: "model.medium_multilingual"
        case .largeV3Multilingual: "model.large_v3_multilingual"
        }
    }

    var detailKey: String {
        switch self {
        case .tinyEnglish, .tinyMultilingual: "model.detail.fastest"
        case .baseEnglish, .baseMultilingual: "model.detail.fast"
        case .smallEnglish, .smallMultilingual: "model.detail.balanced"
        case .mediumMultilingual: "model.detail.accurate"
        case .largeV3Multilingual: "model.detail.most_accurate"
        }
    }

    var downloadSize: String {
        switch self {
        case .tinyEnglish: "~153 MB"
        case .baseEnglish: "~147 MB"
        case .smallEnglish: "~487 MB"
        case .tinyMultilingual: "~76.6 MB"
        case .baseMultilingual: "~147 MB"
        case .smallMultilingual: "~486 MB"
        case .mediumMultilingual: "~1.53 GB"
        case .largeV3Multilingual: "~627 MB"
        }
    }

    var isMultilingual: Bool {
        switch self {
        case .tinyEnglish, .baseEnglish, .smallEnglish: false
        case .tinyMultilingual, .baseMultilingual, .smallMultilingual, .mediumMultilingual, .largeV3Multilingual: true
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
        return Self.isDownloaded(in: localFolder)
    }

    static func isDownloaded(in folder: URL) -> Bool {
        let requiredFiles = [
            "config.json",
            "AudioEncoder.mlmodelc/weights/weight.bin",
            "MelSpectrogram.mlmodelc/weights/weight.bin",
            "TextDecoder.mlmodelc/weights/weight.bin"
        ]
        return requiredFiles.allSatisfy { relativePath in
            let file = folder.appendingPathComponent(relativePath)
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
    @Published var interfaceLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(interfaceLanguage.rawValue, forKey: Self.interfaceLanguageDefaultsKey)
        }
    }
    @Published var audioLanguageSelection: AudioLanguageSelection {
        didSet {
            UserDefaults.standard.set(audioLanguageSelection.storedValue, forKey: Self.audioLanguageDefaultsKey)
        }
    }
    @Published var selectedModel: WhisperModelOption {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelDefaultsKey)
            whisper.unload()
            isModelReady = false
            selectedModelIsDownloaded = selectedModel.isDownloaded
            isDownloadingModel = false
            modelDownloadProgress = 0
            if !isBusy {
                statusMessage = selectedModelIsDownloaded
                    ? LocalizedMessage("status.loading_model", localizedModelName(selectedModel))
                    : LocalizedMessage("status.choose_source")
            }
        }
    }
    @Published var transcript = "" {
        didSet {
            guard !isApplyingTranscript, let savedTranscriptURL else { return }
            try? transcript.write(to: savedTranscriptURL, atomically: true, encoding: .utf8)
        }
    }
    @Published private(set) var statusMessage = LocalizedMessage("status.choose_source")
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
    @Published private(set) var errorMessageState = LocalizedMessage("error.generic", "")
    @Published var errorNeedsScreenRecordingPermission = false
    @Published var statusIsError = false
    @Published var audioLevel: CGFloat = 0.02
    @Published var recordingSeconds = 0
    @Published private(set) var completedWithAutomaticLanguage = false
    @Published private(set) var detectedLanguageCode: String?

    private let whisper = WhisperEngine()
    private var microphoneRecorder: MicrophoneRecorder?
    private var systemRecorder: SystemAudioRecorder?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var transcriptionTask: Task<Void, Never>?
    private var isApplyingTranscript = false
    private static let modelDefaultsKey = "selectedWhisperModel"
    private static let interfaceLanguageDefaultsKey = "selectedInterfaceLanguage"
    private static let audioLanguageDefaultsKey = "selectedAudioLanguage"
    private static let maximumRecordingSeconds = 2 * 60 * 60

    init() {
        let savedInterfaceLanguage = UserDefaults.standard.string(forKey: Self.interfaceLanguageDefaultsKey)
        interfaceLanguage = AppLanguage(rawValue: savedInterfaceLanguage ?? "") ?? .system
        audioLanguageSelection = AudioLanguageSelection(
            storedValue: UserDefaults.standard.string(forKey: Self.audioLanguageDefaultsKey)
        )
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

    var status: String {
        AppLocalization.string(statusMessage, language: interfaceLanguage)
    }

    var errorMessage: String {
        AppLocalization.string(errorMessageState, language: interfaceLanguage)
    }

    var interfaceLocale: Locale { interfaceLanguage.locale }
    var interfaceLayoutDirection: LayoutDirection { interfaceLanguage.layoutDirection }
    var supportedAudioLanguageCodes: [String] {
        AppLocalization.supportedAudioLanguageCodes.sorted {
            audioLanguageName($0).localizedStandardCompare(audioLanguageName($1)) == .orderedAscending
        }
    }

    var activeAudioLanguageSelection: AudioLanguageSelection {
        selectedModel.isMultilingual ? audioLanguageSelection : .language("en")
    }

    var audioLanguageDisplayName: String {
        switch activeAudioLanguageSelection {
        case .automatic:
            localized("language.automatic")
        case let .language(code):
            audioLanguageName(code)
        }
    }

    var detectedLanguageDisplayName: String {
        guard let detectedLanguageCode else { return localized("language.unknown") }
        return audioLanguageName(detectedLanguageCode)
    }

    func localized(_ key: String, _ arguments: String...) -> String {
        AppLocalization.string(key, language: interfaceLanguage, arguments: arguments)
    }

    func localized(_ message: LocalizedMessage) -> String {
        AppLocalization.string(message, language: interfaceLanguage)
    }

    func localizedModelName(_ model: WhisperModelOption) -> String {
        localized(model.titleKey)
    }

    func modelDetail(_ model: WhisperModelOption) -> String {
        localized(model.detailKey, model.downloadSize)
    }

    func audioLanguageName(_ code: String) -> String {
        AppLocalization.audioLanguageName(code: code, interfaceLanguage: interfaceLanguage)
    }

    func selectInterfaceLanguage(_ language: AppLanguage) {
        interfaceLanguage = language
    }

    func selectAudioLanguage(_ selection: AudioLanguageSelection) {
        guard selectedModel.isMultilingual, !isBusy else { return }
        audioLanguageSelection = selection
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
        completedWithAutomaticLanguage = false
        detectedLanguageCode = nil
        statusIsError = false
        statusMessage = LocalizedMessage("status.ready_to_transcribe", url.lastPathComponent)
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
                statusMessage = selectedModelIsDownloaded
                    ? LocalizedMessage("status.loading_model", localizedModelName(model))
                    : LocalizedMessage("status.downloading_model", localizedModelName(model), model.downloadSize, "0")

                try await whisper.downloadAndPrepare(model: model) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.selectedModel == model else { return }
                        let clamped = min(1, max(self.modelDownloadProgress, fraction))
                        self.modelDownloadProgress = clamped
                        self.statusMessage = LocalizedMessage(
                            "status.downloading_model",
                            self.localizedModelName(model),
                            model.downloadSize,
                            String(Int(clamped * 100))
                        )
                    }
                }

                modelDownloadProgress = 1
                selectedModelIsDownloaded = true
                isModelReady = true
                statusMessage = LocalizedMessage("status.model_ready", localizedModelName(model))
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
        statusMessage = LocalizedMessage("status.loading_model", localizedModelName(model))

        Task {
            do {
                try await whisper.loadDownloaded(model: model)
                guard selectedModel == model else { return }
                isModelReady = true
                statusMessage = LocalizedMessage("status.choose_source")
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
        statusMessage = LocalizedMessage("status.cancelling")
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
                    statusMessage = LocalizedMessage("status.recording_microphone")

                case .systemAudio:
                    let recorder = SystemAudioRecorder()
                    recorder.onFailure = { [weak self] error in
                        Task { @MainActor in
                            self?.recordingFailed(error)
                        }
                    }
                    try await recorder.start(writingTo: url, onLevel: levelHandler)
                    systemRecorder = recorder
                    statusMessage = LocalizedMessage("status.recording_mac_audio")

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
        statusMessage = LocalizedMessage("status.finishing_recording")

        let microphoneRecorder = microphoneRecorder
        let systemRecorder = systemRecorder
        self.microphoneRecorder = nil
        self.systemRecorder = nil
        let sourceName = localized(source == .microphone ? "source.microphone" : "source.mac_audio")

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
        statusMessage = LocalizedMessage("status.transcript_copied")
    }

    func saveTranscriptAs() {
        guard !transcript.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = savedTranscriptURL?.lastPathComponent ?? "\(localized("transcript.title")).txt"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try transcript.write(to: url, atomically: true, encoding: .utf8)
            savedTranscriptURL = url
            statusIsError = false
            statusMessage = LocalizedMessage("status.saved", url.lastPathComponent)
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

            statusMessage = LocalizedMessage("status.preparing_audio")
            let prepared = try await MediaPreparer.prepare(url) { [weak self] fraction in
                guard let self, self.isTranscribing else { return }
                self.transcriptionProgress = max(
                    self.transcriptionProgress,
                    min(0.1, fraction * 0.1)
                )
            }
            defer { prepared.removeTemporaryFileIfNeeded() }

            statusMessage = LocalizedMessage("status.transcribing")
            let result = try await whisper.transcribe(
                prepared.url,
                model: selectedModel,
                audioLanguage: activeAudioLanguageSelection
            ) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, self.isTranscribing else { return }
                    self.transcriptionProgress = max(
                        self.transcriptionProgress,
                        min(0.99, 0.1 + fraction * 0.9)
                    )
                }
            }

            guard !result.text.isEmpty else { throw AppError.noSpeechFound }
            applyTranscript(result.text)

            let output = try TranscriptStore.save(result.text, suggestedName: suggestedName)
            savedTranscriptURL = output
            completedWithAutomaticLanguage = selectedModel.isMultilingual
                && activeAudioLanguageSelection == .automatic
            detectedLanguageCode = result.languageCode
            transcriptionProgress = 1
            statusMessage = LocalizedMessage("status.done_saved", output.lastPathComponent)
            statusIsError = false
        } catch is CancellationError {
            transcriptionProgress = 0
            statusIsError = false
            statusMessage = LocalizedMessage("status.cancelled")
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
        statusMessage = LocalizedMessage(
            beforeTranscription == nil ? "status.preparing_audio" : "status.finishing_recording"
        )

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
        statusMessage = LocalizedMessage("status.cancelled")
    }

    private func applyTranscript(_ value: String) {
        isApplyingTranscript = true
        transcript = value
        isApplyingTranscript = false
    }

    private func resetForWork() {
        statusIsError = false
        savedTranscriptURL = nil
        completedWithAutomaticLanguage = false
        detectedLanguageCode = nil
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
        if let appError = error as? AppError {
            statusMessage = LocalizedMessage(appError.localizationKey)
            errorMessageState = LocalizedMessage(appError.localizationKey)
        } else {
            statusMessage = LocalizedMessage("error.generic", error.localizedDescription)
            errorMessageState = LocalizedMessage("error.generic", error.localizedDescription)
        }
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

    var localizationKey: String {
        switch self {
        case .invalidSource:
            "error.invalid_source"
        case .microphonePermissionDenied:
            "error.microphone_permission"
        case .screenRecordingPermissionDenied:
            "error.screen_recording_permission"
        case .noDisplayFound:
            "error.no_display"
        case .noSpeechFound:
            "error.no_speech"
        case .modelUnavailable:
            "error.model_unavailable"
        case .modelNotReady:
            "error.model_not_ready"
        case .mediaHasNoAudio:
            "error.no_audio"
        }
    }

    var errorDescription: String? {
        AppLocalization.string(localizationKey, language: .system)
    }
}
