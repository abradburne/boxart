import SwiftUI
import AppKit
import BoxArtCore

@main struct BoxArtApp: App {
    @StateObject private var model = LibraryModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model).frame(minWidth: 1020, minHeight: 680)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    // Refresh the running Dock icon after replacing a locally built app bundle.
                    if let url = Bundle.main.url(forResource: "BoxArt", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                        NSApplication.shared.applicationIconImage = icon
                    }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }.defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showSettings = true }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open ROM Folder…") { model.chooseFolder() }.keyboardShortcut("o").disabled(model.busy)
                Button("Scan Library") { model.scan() }.keyboardShortcut("r").disabled(model.busy)
            }
            CommandMenu("Artwork") {
                Button(model.title(for: model.defaultScope)) { model.run(model.defaultScope) }
                    .keyboardShortcut("g").disabled(model.busy || model.games.isEmpty)
                Button("Get Artwork for All Games") { model.run(.library) }.disabled(model.busy || model.games.isEmpty)
                Button("Preview Without Saving") { model.run(model.defaultScope, save: false) }.disabled(model.busy || model.games.isEmpty)
                Button("Save Unsaved Previews") { model.save() }.disabled(model.busy || model.ready == 0)
                Divider()
                Button("Select All Shown Games") { model.selectAllShown() }.keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Clear Selection") { model.clearSelection() }.keyboardShortcut("d", modifiers: [.command, .shift]).disabled(model.selectedIDs.isEmpty)
                Divider()
                Button("Stop") { model.stop() }.keyboardShortcut(".").disabled(!model.busy)
            }
        }
    }
}
