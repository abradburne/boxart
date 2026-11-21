import SwiftUI
import AppKit
import ImageIO
import BoxArtCore

extension ArtStatus {
    var color: Color {
        switch self {
        case .saved: return .green
        case .ready: return .teal
        case .searching: return .blue
        case .notFound: return .orange
        case .failed, .saveFailed: return .red
        case .missing: return .secondary.opacity(0.4)
        }
    }
}

/// The grid or list of games, with its right-click menu.
struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    let gridView: Bool
    @Binding var showInspector: Bool

    var body: some View {
        let games = model.visible
        if games.isEmpty {
            emptyState
        } else if gridView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 200), spacing: 20)], alignment: .leading, spacing: 24) {
                    ForEach(games) { game in
                        let selected = model.selectedIDs.contains(game.id)
                        Button {
                            let modifiers = NSEvent.modifierFlags
                            model.select(game.id, shift: modifiers.contains(.shift), command: modifiers.contains(.command))
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                CoverView(game: game, width: 148, height: 154).frame(maxWidth: .infinity)
                                Text(game.title).font(.callout.weight(.medium)).lineLimit(2).frame(height: 36, alignment: .topLeading)
                                HStack(spacing: 5) {
                                    Circle().fill(game.status.color).frame(width: 6, height: 6)
                                    Text(game.status.rawValue).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    if model.systems.count != 1 { Text(game.system.name).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                                }
                            }
                            .padding(10)
                            .background(selected ? Color.teal.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.teal.opacity(0.5) : .clear))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .help(game.source.isEmpty ? game.url.lastPathComponent : game.source)
                        .contextMenu { menu(for: game) }
                    }
                }.padding(22)
            }
        } else {
            List(selection: Binding(get: { model.selectedIDs }, set: { model.setListSelection($0) })) {
                ForEach(games) { game in
                    HStack(spacing: 12) {
                        CoverView(game: game, width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title).font(.body.weight(.medium)).lineLimit(1)
                            Text(game.system.name + (game.code.map { " · " + $0 } ?? "") + (game.source.isEmpty ? "" : " · " + game.source))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(game.status.rawValue).font(.caption.weight(.medium)).foregroundStyle(game.status == .missing ? Color.secondary : game.status.color)
                    }
                    .padding(.vertical, 5).tag(game.id)
                    .contextMenu { menu(for: game) }
                }
            }.listStyle(.inset)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.games.isEmpty {
            ContentUnavailableView {
                Label(model.busy ? "Scanning…" : "Bring your games to life", systemImage: "rectangle.stack")
            } description: {
                Text(model.busy ? model.folder : "Choose your Roms folder, or a single console’s folder, to find its games.")
            } actions: {
                if !model.busy { Button("Choose folder…") { model.chooseFolder() } }
            }
        } else {
            ContentUnavailableView {
                Label("No games here", systemImage: "rectangle.stack")
            } description: {
                Text("Nothing matches this search and status.")
            } actions: {
                Button("Show all") { model.query = ""; model.filter = .all }
            }
        }
    }

    /// Acts on the whole selection when the clicked game is part of it, otherwise on that game alone.
    @ViewBuilder private func menu(for game: Game) -> some View {
        let ids: Set<String> = model.selectedIDs.contains(game.id) ? model.selectedIDs : [game.id]
        let targets = model.games.filter { ids.contains($0.id) }
        let several = ids.count > 1
        Button(several ? "Get Artwork for \(ids.count) Games" : "Get Artwork", systemImage: "arrow.down.circle") {
            model.getArtwork(ids: ids)
        }.disabled(model.busy || targets.allSatisfy { $0.savedURL != nil })
        Button(several ? "Find Previews Without Saving" : "Find Preview Without Saving", systemImage: "magnifyingglass") {
            model.download(ids: ids)
        }.disabled(model.busy || targets.allSatisfy { $0.savedURL != nil || $0.artwork != nil })
        let previews = targets.filter { $0.savedURL == nil && $0.artwork != nil }.count
        Button(several ? "Save \(previews) Previews" : "Save Preview", systemImage: "square.and.arrow.down") {
            model.save(ids: ids)
        }.disabled(model.busy || previews == 0)
        if !several {
            Button("Import Image…", systemImage: "photo") { model.importImage(for: game.id) }
                .disabled(model.busy || game.savedURL != nil)
            Button("Search Images Online…", systemImage: "globe") {
                var components = URLComponents(string: "https://www.google.com/search")!
                components.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: "\(game.title) \(game.system.name) \(model.kind.rawValue.lowercased())")]
                if let url = components.url { NSWorkspace.shared.open(url) }
            }
        }
        Divider()
        if !several {
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([game.savedURL ?? game.url]) }
            if game.savedURL != nil {
                Button("Show ROM in Finder", systemImage: "doc") { NSWorkspace.shared.activateFileViewerSelecting([game.url]) }
            }
            Button("Show Info", systemImage: "info.circle") { model.select(game.id); showInspector = true }
        }
        Button(several ? "Move Saved Artwork to Trash" : "Move Artwork to Trash", systemImage: "trash", role: .destructive) {
            model.removeArtwork(for: ids)
        }.disabled(model.busy || !targets.contains { $0.savedURL != nil })
    }
}

/// Details for the focused game.
struct InspectorView: View {
    @ObservedObject var model: LibraryModel

    var body: some View {
        ScrollView {
            if let game = model.selected {
                VStack(alignment: .leading, spacing: 18) {
                    Text("ARTWORK PREVIEW").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    CoverView(game: game, width: 232, height: 216)
                    Text(game.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Circle().fill(game.status.color).frame(width: 7, height: 7)
                        Text(game.status.rawValue).font(.callout.weight(.medium))
                    }
                    Text(game.source.isEmpty ? "Find artwork to preview the matching cover before saving it to your card." : game.source)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    field("CONSOLE", game.system.name + (game.code.map { " · " + $0 } ?? ""))
                    field("ROM FILE", game.url.lastPathComponent)
                    field("OUTPUT", (try? model.settings.output(for: game.url).path) ?? "Choose a destination in Settings")
                    field("IMAGE", model.profile == .twilight ? "PNG · fits within 128 × 115" : "\(model.settings.writesJPEG ? "JPEG" : "PNG") · up to \(model.size) px · preserves proportions")
                    if game.savedURL == nil {
                        Button("Get artwork for this game") { model.getArtwork(ids: [game.id]) }.disabled(model.busy)
                        Button("Import image…") { model.importImage(for: game.id) }.disabled(model.busy)
                    } else if let url = game.savedURL {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        Button("Move artwork to Trash", role: .destructive) { model.removeArtwork(for: [game.id]) }.disabled(model.busy)
                    }
                }.padding(24)
            } else {
                ContentUnavailableView("Select a game", systemImage: "photo", description: Text("Preview its artwork and export location.")).padding(.top, 70)
            }
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Decoded, downsized covers. Full-size images are never held for the grid.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, CGImage>()
    private init() { cache.countLimit = 1500 }

    func image(for key: String) -> CGImage? { cache.object(forKey: key as NSString) }
    /// A cover replaced on disk keeps its path, so its old thumbnail has to be dropped by hand.
    func remove(_ key: String?) { if let key { cache.removeObject(forKey: key as NSString) } }
    func removeAll() { cache.removeAllObjects() }

    func load(key: String, data: Data?, url: URL?) async -> CGImage? {
        if let hit = image(for: key) { return hit }
        let image = await Task.detached(priority: .utility) { () -> CGImage? in
            let source: CGImageSource?
            if let data { source = CGImageSourceCreateWithData(data as CFData, nil) }
            else if let url { source = CGImageSourceCreateWithURL(url as CFURL, nil) }
            else { source = nil }
            guard let source else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 480]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }
}

/// A game's cover: the unsaved preview if there is one, else the saved file, loaded off the main thread.
struct CoverView: View {
    let game: Game
    let width: CGFloat
    let height: CGFloat
    @State private var image: CGImage?

    static func key(for game: Game) -> String? {
        if let data = game.artwork { return "preview:\(game.id):\(data.count)" }
        if let url = game.savedURL { return "saved:\(url.path)" }
        return nil
    }
    private var key: String? { Self.key(for: game) }

    var body: some View {
        let shown = key == nil ? nil : image ?? key.flatMap(ThumbnailCache.shared.image)
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07))
            if let shown {
                Image(decorative: shown, scale: 1).resizable().aspectRatio(contentMode: .fit).padding(width > 100 ? 8 : 2)
            } else if game.status == .searching {
                ProgressView().controlSize(width > 100 ? .regular : .small)
            } else {
                Image(systemName: "photo").font(width > 100 ? .system(size: 42, weight: .ultraLight) : .body).foregroundStyle(.tertiary)
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel(key == nil ? "No cover artwork" : "Cover for \(game.title)")
        .task(id: key) {
            guard let key else { image = nil; return }
            let loaded = await ThumbnailCache.shared.load(key: key, data: game.artwork, url: game.savedURL)
            if !Task.isCancelled { image = loaded }
        }
    }
}
