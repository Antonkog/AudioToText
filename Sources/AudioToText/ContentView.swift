import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var controller: TranscriptionController
    @State private var isShowingAudioLanguagePicker = false

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            Circle()
                .fill(AppTheme.accentSoft.opacity(0.45))
                .frame(width: 380, height: 380)
                .blur(radius: 40)
                .offset(x: 330, y: -280)

            VStack(spacing: 18) {
                header
                sourceCard
                transcriptCard
            }
            .padding(28)
        }
        .foregroundStyle(AppTheme.ink)
        .fileImporter(
            isPresented: $controller.isShowingImporter,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            controller.handleImport(result)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $controller.isDropTargeted) { providers in
            controller.handleDrop(providers)
        }
        .alert("AudioToText", isPresented: $controller.isShowingError) {
            Button(controller.localized("button.ok"), role: .cancel) {}
        } message: {
            Text(controller.errorMessage)
        }
        .onOpenURL { url in
            controller.selectFile(url)
            controller.transcribeSelectedFile()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(AppTheme.ink)
                    .frame(width: 52, height: 52)

                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AudioToText")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(controller.localized("app.subtitle"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer()

            Menu {
                Button {
                    controller.selectInterfaceLanguage(.system)
                } label: {
                    languageMenuLabel(
                        controller.localized("language.system_default"),
                        selected: controller.interfaceLanguage == .system
                    )
                }

                Divider()

                ForEach(AppLanguage.selectableLanguages) { language in
                    Button {
                        controller.selectInterfaceLanguage(language)
                    } label: {
                        languageMenuLabel(
                            language.nativeName,
                            selected: controller.interfaceLanguage == language
                        )
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(AppTheme.teal, in: Circle())

                    Text(
                        controller.interfaceLanguage == .system
                        ? controller.localized("language.system_default")
                        : controller.interfaceLanguage.nativeName
                    )
                    .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .padding(.leading, 5)
                .padding(.trailing, 9)
                .padding(.vertical, 4)
                .background(.white.opacity(0.78), in: Capsule())
                .overlay(Capsule().stroke(AppTheme.teal.opacity(0.22), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .tint(AppTheme.ink)
            .fixedSize()
            .help(controller.localized("settings.interface_language"))

            HStack(spacing: 7) {
                Circle()
                    .fill(controller.isModelReady ? AppTheme.teal : AppTheme.accent)
                    .frame(width: 8, height: 8)
                Text(controller.localized(controller.isModelReady ? "header.whisper_ready" : "header.free_local_model"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.72), in: Capsule())
        }
    }

    private func languageMenuLabel(_ title: String, selected: Bool) -> some View {
        Label(title, systemImage: selected ? "checkmark" : "circle.fill")
    }

    private func modelMenuButton(_ model: WhisperModelOption) -> some View {
        Button {
            controller.selectModel(model)
        } label: {
            HStack {
                Text(controller.localizedModelName(model))
                Text(model.downloadSize)
                if controller.selectedModel == model {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private var sourceCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 4) {
                ForEach(AudioSource.allCases) { source in
                    Button {
                        controller.source = source
                    } label: {
                        Label(controller.localized(source.titleKey), systemImage: source.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(controller.source == source ? Color.white : AppTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(
                                controller.source == source ? AppTheme.ink : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .disabled(controller.isBusy)
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Label(controller.localized("model.title"), systemImage: "cpu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedInk)

                    Menu {
                        Section(controller.localized("model.group.english")) {
                            ForEach(WhisperModelOption.englishModels) { model in
                                modelMenuButton(model)
                            }
                        }

                        Section(controller.localized("model.group.multilingual")) {
                            ForEach(WhisperModelOption.multilingualModels) { model in
                                modelMenuButton(model)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(controller.localizedModelName(controller.selectedModel))
                                .lineLimit(1)
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

                    Text(controller.modelDetail(controller.selectedModel))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.mutedInk)

                    Spacer()

                    HStack(spacing: 7) {
                        Button {
                            controller.performModelAction()
                        } label: {
                            Label(controller.localized("button.download"), systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(ModelActionButtonStyle())
                        .disabled(controller.isDownloadingModel || controller.selectedModelIsDownloaded)

                        if controller.selectedModelIsDownloaded {
                            Button {
                                controller.openSelectedModelInFinder()
                            } label: {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppTheme.teal)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        AppTheme.teal.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(controller.localized("help.open_model"))
                        }
                    }
                }

                HStack(spacing: 12) {
                    Label(controller.localized("language.audio_title"), systemImage: "character.bubble")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedInk)

                    Button {
                        isShowingAudioLanguagePicker.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(controller.audioLanguageDisplayName)
                                .lineLimit(1)
                            if controller.selectedModel.isMultilingual {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isBusy || !controller.selectedModel.isMultilingual)
                    .popover(isPresented: $isShowingAudioLanguagePicker, arrowEdge: .bottom) {
                        AudioLanguagePickerView()
                            .environmentObject(controller)
                    }

                    Text(
                        controller.selectedModel.isMultilingual
                            ? controller.localized("language.multilingual_hint")
                            : controller.localized("language.english_model_hint")
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.mutedInk)

                    Spacer()
                }

                if controller.isDownloadingModel {
                    HStack(spacing: 10) {
                        ProgressView(value: controller.modelDownloadProgress, total: 1)
                            .progressViewStyle(.linear)
                            .tint(AppTheme.teal)

                        Text("\(Int(controller.modelDownloadProgress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.mutedInk)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 3)

            HStack(spacing: 18) {
                sourceIllustration

                VStack(alignment: .leading, spacing: 8) {
                    Text(controller.localized(controller.source.headlineKey))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(controller.localized(controller.source.instructionsKey))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if let selectedFile = controller.selectedFile {
                        Label(selectedFile.lastPathComponent, systemImage: "doc.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 12)

                actionButton
            }

            if controller.isRecording {
                recordingMeter
            }

            if controller.shouldShowStatusRow {
                HStack(spacing: 8) {
                    if controller.isBusy && !controller.isRecording && !controller.isTranscribing {
                        ProgressView().controlSize(.small)
                    } else if controller.savedTranscriptURL != nil {
                        Button {
                            controller.revealSavedTranscriptInFinder()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(controller.status)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.teal)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(controller.localized("help.show_saved_transcript"))
                    } else {
                        Image(systemName: controller.statusSymbol)
                            .foregroundStyle(controller.statusIsError ? AppTheme.accent : AppTheme.teal)

                        Text(controller.status)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    Spacer()

                    Text(controller.localized("privacy.no_api_fee"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.teal)
                }
            }
        }
        .padding(20)
        .cardStyle()
    }

    private var sourceIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.accentSoft.opacity(0.7))
                .frame(width: 72, height: 72)
            Image(systemName: controller.source.symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppTheme.accent)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if controller.isTranscribing {
            HStack(spacing: 12) {
                CircularProgressView(progress: controller.transcriptionProgress)

                Button {
                    controller.cancelTranscription()
                } label: {
                    Label(controller.localized("button.cancel"), systemImage: "xmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle(isDestructive: true))
            }
            .transition(.opacity)
        } else {
            switch controller.source {
            case .file:
                Button {
                    if controller.selectedFile == nil {
                        controller.isShowingImporter = true
                    } else if controller.savedTranscriptURL != nil {
                        controller.chooseAnotherFile()
                    } else {
                        controller.transcribeSelectedFile()
                    }
                } label: {
                    Label(
                        controller.selectedFile == nil || controller.savedTranscriptURL != nil
                            ? controller.localized(
                                controller.savedTranscriptURL == nil ? "button.choose_file" : "button.choose_another"
                            )
                            : controller.localized("button.transcribe"),
                        systemImage: controller.selectedFile == nil || controller.savedTranscriptURL != nil
                            ? "folder"
                            : "text.badge.checkmark"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(controller.isBusy)

            case .systemAudio, .microphone:
                Button {
                    controller.isRecording ? controller.stopRecording() : controller.startRecording()
                } label: {
                    Label(
                        controller.localized(
                            controller.isRecording ? "button.stop_transcribe" : "button.start_recording"
                        ),
                        systemImage: controller.isRecording ? "stop.fill" : "record.circle"
                    )
                }
                .buttonStyle(PrimaryButtonStyle(isDestructive: controller.isRecording))
                .disabled(controller.isBusy && !controller.isRecording)
            }
        }
    }

    private var recordingMeter: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 9, height: 9)
                .shadow(color: AppTheme.accent.opacity(0.6), radius: 6)

            Text(controller.recordingDurationText)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.07))
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: max(8, geometry.size.width * controller.audioLevel))
                }
            }
            .frame(height: 7)
        }
        .padding(.horizontal, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var transcriptCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.localized("transcript.title"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    if let output = controller.savedTranscriptURL {
                        Button {
                            controller.revealSavedTranscriptInFinder()
                        } label: {
                            Label(
                                controller.localized("transcript.saved_to", output.lastPathComponent),
                                systemImage: "folder.fill"
                            )
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.teal)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(controller.localized("help.show_path", output.path))
                    } else {
                        Text(controller.localized("transcript.editable"))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                if controller.completedWithAutomaticLanguage {
                    Label(
                        controller.localized(
                            "language.detected",
                            controller.detectedLanguageDisplayName
                        ),
                        systemImage: "character.magnify"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.teal)
                    .padding(.trailing, 8)
                }

                Spacer()

                Button {
                    controller.copyTranscript()
                } label: {
                    Label(controller.localized("button.copy"), systemImage: "doc.on.doc")
                }
                .disabled(controller.transcript.isEmpty)

                Button {
                    controller.saveTranscriptAs()
                } label: {
                    Label(controller.localized("button.save_txt"), systemImage: "square.and.arrow.down")
                }
                .disabled(controller.transcript.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().opacity(0.55)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $controller.transcript)
                    .font(.system(size: 14, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(12)

                if controller.transcript.isEmpty {
                    Text(controller.localized("transcript.placeholder"))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.mutedInk.opacity(0.72))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .background(controller.isDropTargeted ? AppTheme.accentSoft.opacity(0.45) : Color.clear)
        }
        .frame(maxHeight: .infinity)
        .cardStyle()
    }
}

private struct AudioLanguagePickerView: View {
    @EnvironmentObject private var controller: TranscriptionController
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredCodes: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return controller.supportedAudioLanguageCodes }
        return controller.supportedAudioLanguageCodes.filter { code in
            code.localizedCaseInsensitiveContains(query)
                || controller.audioLanguageName(code).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.localized("language.choose_audio"))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            TextField(controller.localized("language.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(spacing: 3) {
                    languageButton(
                        title: controller.localized("language.automatic"),
                        subtitle: controller.localized("language.automatic_hint"),
                        selection: .automatic
                    )

                    Divider().padding(.vertical, 4)

                    ForEach(filteredCodes, id: \.self) { code in
                        languageButton(
                            title: controller.audioLanguageName(code),
                            subtitle: code.uppercased(),
                            selection: .language(code)
                        )
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 330, height: 430)
    }

    private func languageButton(
        title: String,
        subtitle: String,
        selection: AudioLanguageSelection
    ) -> some View {
        Button {
            controller.selectAudioLanguage(selection)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if controller.audioLanguageSelection == selection {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.teal)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            controller.audioLanguageSelection == selection
                ? AppTheme.teal.opacity(0.1)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

private struct CircularProgressView: View {
    @EnvironmentObject private var controller: TranscriptionController
    let progress: Double

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.teal.opacity(0.16), lineWidth: 4)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    AppTheme.teal,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(clampedProgress * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
        }
        .frame(width: 48, height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(controller.localized("progress.transcription"))
        .accessibilityValue(
            controller.localized("progress.percent", String(Int(clampedProgress * 100)))
        )
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 17)
            .padding(.vertical, 11)
            .background(
                isDestructive ? AppTheme.accent : AppTheme.ink,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct ModelActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppTheme.teal, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.48)
    }
}
