import SwiftUI

@main
struct AudioToTextApp: App {
    @StateObject private var controller = TranscriptionController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 760, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Audio or Video…") {
                    controller.isShowingImporter = true
                }
                .keyboardShortcut("o")
            }

            CommandGroup(after: .saveItem) {
                Button("Save Transcript As…") {
                    controller.saveTranscriptAs()
                }
                .keyboardShortcut("s")
                .disabled(controller.transcript.isEmpty)
            }
        }
    }
}
