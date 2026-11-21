import SwiftUI
import BoxArtCore

struct SettingsView: View {
    @ObservedObject var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Artwork settings").font(.title2.bold())
            Form {
                Picker("Export profile", selection: $model.profile) { ForEach(Profile.allCases) { Text($0.rawValue).tag($0) } }
                Text(model.profile.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.profile != .twilight {
                    Picker("Maximum edge", selection: $model.size) { ForEach([128, 256, 512, 1024], id: \.self) { Text("\($0) px").tag($0) } }
                }
                if model.profile == .custom && model.kind == .box {
                    Picker("Format", selection: $model.jpeg) { Text("PNG").tag(false); Text("JPEG").tag(true) }
                }
                if model.profile != .anbernic {
                    LabeledContent("Destination") {
                        HStack {
                            Text(model.settings.destination?.path ?? "None chosen").font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                            Button("Choose…") { model.chooseFolder(destination: true) }
                        }
                    }
                }
                if model.profile == .retroarch {
                    Text("Created automatically when saving. Set RetroArch’s Settings → Directory → Thumbnails to this folder on your device.").font(.caption).foregroundStyle(.secondary)
                    Button("Import .lpl playlists…") { model.importPlaylists() }.disabled(model.games.isEmpty)
                    Text("\(model.identities.count) playlist labels matched").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Rename ROMs to their Libretro names", isOn: $model.normalizeFilenames)
                Text("Renames each ROM to its uniquely matched artwork title, keeping its extension. Off by default. Skips ambiguous matches, existing artwork and playlist-based libraries, and saves a rename log beside the ROMs.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.disabled(model.busy)
            Divider()
            Text("Box art comes from Libretro by filename, then by title, and from GameTDB by DS game code. Cart labels come from GameTDB (DS) and the slot CFW art set (Game Boy, Color and Advance). Existing artwork is never overwritten.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("GameTDB", destination: URL(string: "https://www.gametdb.com")!)
                Link("Libretro", destination: URL(string: "https://github.com/libretro-thumbnails/libretro-thumbnails")!)
                Spacer()
                Button("Done") { model.showSettings = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 520)
    }
}
