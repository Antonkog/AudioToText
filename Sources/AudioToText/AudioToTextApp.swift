import SwiftUI

@main
struct AudioToTextApp: App {
    @StateObject private var controller = TranscriptionController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .environment(\.locale, controller.interfaceLocale)
                .environment(\.layoutDirection, controller.interfaceLayoutDirection)
                .frame(minWidth: 760, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(controller.localized("command.open_audio_video")) {
                    controller.isShowingImporter = true
                }
                .keyboardShortcut("o")
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
