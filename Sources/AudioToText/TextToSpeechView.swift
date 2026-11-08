import SwiftUI

struct TextToSpeechView: View {
    @EnvironmentObject private var app: TranscriptionController
    @EnvironmentObject private var controller: TextToSpeechController
    @State private var pendingAlert: PendingTTSAlert?
    @State private var pendingModel: TTSModelOption?

    var body: some View {
        VStack(spacing: 18) {
            modelCard
            editorCard
        }
        .alert(item: $pendingAlert) { alert in
            switch alert {
            case .lowMemory:
                Alert(
                    title: Text(app.localized("tts.warning.memory_title")),
                    message: Text(app.localized("tts.warning.memory_message", String(SystemCompatibility.current(for: .quality).memoryGB))),
                    primaryButton: .default(Text(app.localized("tts.warning.use_compact"))) {
                        pendingModel = nil
                        controller.selectModel(.compact)
                    },
                    secondaryButton: .destructive(Text(app.localized("tts.warning.continue"))) {
                        if let pendingModel { controller.selectModel(pendingModel) }
                        pendingModel = nil
                    }
                )
            case .download:
                Alert(
                    title: Text(app.localized("tts.download.title")),
                    message: Text(app.localized(
                        "tts.download.message",
                        app.localized(controller.selectedModel.titleKey),
                        controller.selectedModel.downloadSize,
                        controller.compatibility.freeDiskDescription
                    )),
                    primaryButton: .default(Text(app.localized("button.download"))) {
                        controller.downloadSelectedModel()
                    },
                    secondaryButton: .cancel(Text(app.localized("button.cancel")))
                )
            }
        }
        .alert("AudioToText", isPresented: $controller.isShowingError) {
            Button(app.localized("button.ok"), role: .cancel) {}
        } message: {
            Text(app.localized(controller.errorMessageState))
        }
    }

    private var modelCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Label(app.localized("tts.model_title"), systemImage: "cpu")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedInk)

                Menu {
                    ForEach(TTSModelOption.allCases) { model in
                        Button {
                            selectModel(model)
                        } label: {
                            HStack {
                                Text(app.localized(model.titleKey))
                                Text(model.downloadSize)
                                if model == controller.selectedModel { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(app.localized(controller.selectedModel.titleKey))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)
                .tint(AppTheme.ink)
                .fixedSize()
                .disabled(controller.isBusy)

                Text(app.localized(controller.selectedModel.detailKey, controller.selectedModel.downloadSize))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.mutedInk)

                Spacer()

                if controller.isDownloadingModel {
                    Button {
                        controller.cancelDownload()
                    } label: {
                        Label(app.localized("button.cancel"), systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(ModelActionButtonStyle())
                } else {
                    Button {
                        controller.refreshCompatibility()
                        pendingAlert = .download
                    } label: {
                        Label(app.localized("button.download"), systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(ModelActionButtonStyle())
                    .disabled(controller.selectedModelIsDownloaded || !controller.compatibility.isSupported || controller.isBusy)
                }

                if controller.selectedModelIsDownloaded {
                    Button {
                        controller.openModelInFinder()
                    } label: {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.teal)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(app.localized("help.open_model"))
                }
            }

            if controller.isDownloadingModel {
                HStack(spacing: 10) {
                    ProgressView(value: controller.modelDownloadProgress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.teal)
                    Text("\(Int(controller.modelDownloadProgress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(width: 40, alignment: .trailing)
                }
            }

            HStack(spacing: 9) {
                Image(systemName: controller.compatibility.isSupported ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(controller.compatibility.isSupported ? AppTheme.teal : AppTheme.accent)
                Text(compatibilityText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.mutedInk)
                Spacer()
                Text(app.localized("privacy.no_api_fee"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.teal)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private var editorCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.localized("tts.text_title"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(app.localized("tts.text_hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer()

                Picker(app.localized("tts.language_title"), selection: $controller.selectedLanguage) {
                    ForEach(TTSSpeechLanguage.allCases) { language in
                        Text(app.localized(language.titleKey)).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(controller.isBusy)

                Picker(app.localized("tts.voice_title"), selection: $controller.selectedVoice) {
                    ForEach(TTSVoice.allCases) { voice in
                        Text(voice.displayName).tag(voice)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(controller.isBusy)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $controller.inputText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.black.opacity(0.06)))
                    .disabled(controller.isBusy)

                if controller.inputText.isEmpty {
                    Text(app.localized("tts.placeholder"))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.mutedInk.opacity(0.72))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 170)

            HStack(spacing: 12) {
                statusView
                Spacer()
                controls
            }
        }
        .padding(18)
        .cardStyle()
    }

    @ViewBuilder
    private var statusView: some View {
        if let saved = controller.savedAudioURL {
            Button {
                controller.revealSavedAudioInFinder()
            } label: {
                Label(app.localized(controller.statusMessage), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.teal)
            }
            .buttonStyle(.plain)
            .help(app.localized("help.show_path", saved.path))
        } else {
            HStack(spacing: 7) {
                if controller.isBusy && !controller.isGenerating && !controller.isDownloadingModel {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: controller.hasGeneratedAudio ? "checkmark.circle.fill" : "waveform")
                        .foregroundStyle(AppTheme.teal)
                }
                Text(app.localized(controller.statusMessage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if controller.isGenerating {
            HStack(spacing: 12) {
                TTSProgressRing(progress: controller.generationProgress)
                Button {
                    controller.cancelGeneration()
                } label: {
                    Label(app.localized("button.cancel"), systemImage: "xmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle(isDestructive: true))
            }
        } else if controller.hasGeneratedAudio {
            HStack(spacing: 8) {
                Button {
                    controller.isPlaying ? controller.pausePlayback() : controller.play()
                } label: {
                    Label(
                        app.localized(controller.isPlaying ? "tts.button.pause" : "tts.button.play"),
                        systemImage: controller.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    controller.stopPlayback()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                .help(app.localized("tts.button.stop"))

                Button(app.localized("tts.button.save_m4a")) {
                    controller.saveM4A(
                        title: app.localized("tts.save.m4a_title"),
                        prompt: app.localized("tts.save.prompt")
                    )
                }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(controller.isBusy)
                Button(app.localized("tts.button.save_mp3")) {
                    controller.saveMP3(
                        title: app.localized("tts.save.mp3_title"),
                        prompt: app.localized("tts.save.prompt")
                    )
                }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(controller.isBusy)
            }
        } else {
            Button {
                controller.generate()
            } label: {
                Label(app.localized("tts.button.generate"), systemImage: "waveform.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!controller.canGenerate)
        }
    }

    private var compatibilityText: String {
        let item = controller.compatibility
        if !item.isAppleSilicon { return app.localized("tts.compatibility.apple_silicon") }
        if item.operatingSystemMajorVersion < 15 { return app.localized("tts.compatibility.macos") }
        if !item.hasMinimumDisk { return app.localized("tts.compatibility.disk_blocked", item.freeDiskDescription) }
        if item.shouldWarnMemory { return app.localized("tts.compatibility.memory_warning", String(item.memoryGB)) }
        if item.hasLowDiskHeadroom { return app.localized("tts.compatibility.disk_warning", item.freeDiskDescription) }
        return app.localized("tts.compatibility.ready", String(item.memoryGB), item.freeDiskDescription)
    }

    private func selectModel(_ model: TTSModelOption) {
        let compatibility = SystemCompatibility.current(for: model)
        if model == .quality, compatibility.shouldWarnMemory {
            pendingModel = model
            pendingAlert = .lowMemory
        } else {
            controller.selectModel(model)
        }
    }
}

private enum PendingTTSAlert: String, Identifiable {
    case lowMemory, download
    var id: String { rawValue }
}

private struct TTSProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.09), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(AppTheme.teal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .frame(width: 46, height: 46)
    }
}
