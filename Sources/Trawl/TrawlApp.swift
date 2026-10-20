import AppKit
import SwiftUI

@main
struct TrawlApp: App {
    @StateObject private var model = SearchModel()

    init() {
        // Needed when launched as a bare executable (swift run) rather than from the .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        Window("Trawl", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 460)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Folder…") { model.chooseFolders() }
                    .keyboardShortcut("o")
            }
        }
    }
}
