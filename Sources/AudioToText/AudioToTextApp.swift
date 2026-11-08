import SwiftUI

@main
struct AudioToTextApp: App {
    @StateObject private var controller = TranscriptionController()
    @StateObject private var ttsController = TextToSpeechController()
    @AppStorage("selectedAppMode") private var selectedModeRaw = AppMode.audioToText.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .environmentObject(ttsController)
                .environment(\.locale, controller.interfaceLocale)
                .environment(\.layoutDirection, controller.interfaceLayoutDirection)
                .preferredColorScheme(.light)
                .frame(minWidth: 780, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(controller.localized("command.open_audio_video")) {
                    controller.isShowingImporter = true
                }
                .keyboardShortcut("o")
                .disabled(selectedModeRaw != AppMode.audioToText.rawValue)
            }

            CommandGroup(after: .saveItem) {
                Button(controller.localized("command.save_transcript_as")) {
                    controller.saveTranscriptAs()
                }
                .keyboardShortcut("s")
                .disabled(controller.transcript.isEmpty)
            }
        }
    }
}
