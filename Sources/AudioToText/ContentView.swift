import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var controller: TranscriptionController

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
            if controller.errorNeedsScreenRecordingPermission {
                Button("Open Screen Recording Settings") {
                    controller.openScreenRecordingSettings()
                }
            }
            Button("OK", role: .cancel) {}
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
                Text("Private English transcription on your Mac")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(controller.isModelReady ? AppTheme.teal : AppTheme.accent)
                    .frame(width: 8, height: 8)
                Text(controller.isModelReady ? "Whisper ready" : "Free local model")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.72), in: Capsule())
        }
    }

    private var sourceCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 4) {
                ForEach(AudioSource.allCases) { source in
                    Button {
                        controller.source = source
                    } label: {
                        Label(source.title, systemImage: source.symbol)
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
                    Label("Whisper model", systemImage: "cpu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedInk)

                    HStack(spacing: 3) {
                        ForEach(WhisperModelOption.allCases) { model in
                            Button {
                                controller.selectModel(model)
                            } label: {
                                Text(model.title.replacingOccurrences(of: " English", with: ""))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(controller.selectedModel == model ? Color.white : AppTheme.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                    .background(
                                        controller.selectedModel == model ? AppTheme.teal : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(controller.isBusy)
                        }
                    }
                    .padding(3)
                    .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Text(controller.selectedModel.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.mutedInk)

                    Spacer()

                    HStack(spacing: 7) {
                        Button {
                            controller.performModelAction()
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle.fill")
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
                            .help("Open model in Finder")
                        }
                    }
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
                    Text(controller.source.headline)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(controller.source.instructions)
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
                        .help("Show saved transcript in Finder")
                    } else {
                        Image(systemName: controller.statusSymbol)
                            .foregroundStyle(controller.statusIsError ? AppTheme.accent : AppTheme.teal)

                        Text(controller.status)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    Spacer()

                    Text("No API key · no usage fee")
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
                    Label("Cancel", systemImage: "xmark.circle.fill")
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
                            ? (controller.savedTranscriptURL == nil ? "Choose File" : "Choose Another")
                            : "Transcribe",
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
                        controller.isRecording ? "Stop & Transcribe" : "Start Recording",
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
                    Text("Transcript")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    if let output = controller.savedTranscriptURL {
                        Button {
                            controller.revealSavedTranscriptInFinder()
                        } label: {
                            Label("Saved to \(output.lastPathComponent)", systemImage: "folder.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.teal)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show \(output.path) in Finder")
                    } else {
                        Text("Your text stays editable")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                Spacer()

                Button {
                    controller.copyTranscript()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(controller.transcript.isEmpty)

                Button {
                    controller.saveTranscriptAs()
                } label: {
                    Label("Save .txt", systemImage: "square.and.arrow.down")
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
                    Text("Drop an audio/video file here, record a conversation, or capture audio playing from YouTube and other apps.")
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

private struct CircularProgressView: View {
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
        .accessibilityLabel("Transcription progress")
        .accessibilityValue("\(Int(clampedProgress * 100)) percent")
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
