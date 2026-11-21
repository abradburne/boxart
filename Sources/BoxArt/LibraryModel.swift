import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BoxArtCore

/// The status chips above the library.
enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All", missing = "Missing", unsaved = "Unsaved", saved = "Saved"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .missing: return "photo.badge.exclamationmark"
        case .unsaved: return "arrow.down.circle"
        case .saved: return "checkmark.circle"
        }
    }
    func includes(_ game: Game) -> Bool {
        switch self {
        case .all: return true
        case .missing: return game.savedURL == nil && game.artwork == nil
        case .unsaved: return game.savedURL == nil && game.artwork != nil
        case .saved: return game.savedURL != nil
        }
    }
}

/// Which games an action applies to.
enum Scope {
    /// The games selected in the grid or list.
    case selection
    /// Everything currently listed: the chosen consoles, narrowed by search and status.
    case shown
    /// Every scanned game.
    case library
}

@MainActor final class LibraryModel: ObservableObject {
    /// Tests get a throwaway store so they neither read nor disturb the app's settings.
    private static let defaults: UserDefaults = NSClassFromString("XCTestCase") == nil ? .standard : UserDefaults(suiteName: "boxart-tests-\(ProcessInfo.processInfo.processIdentifier)")!

    // MARK: Library

    @Published var folder = defaults.string(forKey: "romFolder") ?? "/Volumes/DS/Roms"
    @Published var games: [Game] = []
    @Published var identities: [String: PlaylistIdentity] = [:]

    // MARK: Narrowing

    @Published var query = ""
    @Published var filter: StatusFilter = .all
    /// Consoles chosen in the sidebar; empty shows them all.
    @Published var systems: Set<GameSystem> = []

    // MARK: Selection

    @Published var selection: String?
    @Published var selectedIDs: Set<String> = []
    private var selectionAnchor: String?

    // MARK: Settings

    @Published var showSettings = false
    @Published var profile = Profile(rawValue: defaults.string(forKey: "profile") ?? "") ?? .anbernic {
        didSet { Self.defaults.set(profile.rawValue, forKey: "profile") }
    }
    @Published var kind = ArtKind(rawValue: defaults.string(forKey: "artKind") ?? "") ?? .box {
        didSet { Self.defaults.set(kind.rawValue, forKey: "artKind") }
    }
    @Published var size = defaults.object(forKey: "maxSize") as? Int ?? 512 {
        didSet { Self.defaults.set(size, forKey: "maxSize") }
    }
    @Published var jpeg = defaults.bool(forKey: "jpeg") {
        didSet { Self.defaults.set(jpeg, forKey: "jpeg") }
    }
    @Published var normalizeFilenames = defaults.bool(forKey: "normalizeFilenames") {
        didSet { Self.defaults.set(normalizeFilenames, forKey: "normalizeFilenames") }
    }
    @Published var destination = defaults.string(forKey: "destination").map { URL(fileURLWithPath: $0, isDirectory: true) } {
        didSet { Self.defaults.set(destination?.path, forKey: "destination") }
    }

    // MARK: Activity

    @Published var busy = false
    @Published var progress = 0.0
    @Published var message = "Connect your SD card to get started."
    @Published var error: String?
    private var job: Task<Void, Never>?
    let service = ArtworkService()
    /// Lookups and saves that run at once. Enough to keep an SD card and the artwork servers busy without flooding either.
    private let parallelism = 6

    var settings: ExportSettings {
        var s = ExportSettings()
        s.profile = profile; s.kind = kind; s.maxSize = size; s.jpeg = jpeg; s.identities = identities
        s.destination = destination ?? (profile == .retroarch ? ExportSettings.suggestedRetroArchDirectory(for: URL(fileURLWithPath: folder)) : nil)
        return s
    }

    // MARK: Derived lists

    /// Games in the chosen consoles that match the search, before the status chip is applied.
    var matchingGames: [Game] {
        games.filter { game in
            (systems.isEmpty || systems.contains(game.system))
                && (query.isEmpty || game.title.localizedCaseInsensitiveContains(query) || (game.code?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }
    var visible: [Game] { matchingGames.filter(filter.includes) }
    func filterCount(_ filter: StatusFilter) -> Int { matchingGames.filter(filter.includes).count }
    /// Games holding a preview that is not on the card yet, including ones whose save failed.
    var ready: Int { games.filter { $0.savedURL == nil && $0.artwork != nil }.count }
    var saved: Int { games.filter { $0.savedURL != nil }.count }
    var selected: Game? { games.first { $0.id == selection } }
    /// Saved and total game counts for each console present, in sidebar order.
    var systemCounts: [(system: GameSystem, saved: Int, total: Int)] {
        var totals: [GameSystem: (Int, Int)] = [:]
        for game in games {
            let current = totals[game.system] ?? (0, 0)
            totals[game.system] = (current.0 + (game.savedURL != nil ? 1 : 0), current.1 + 1)
        }
        return GameSystem.allCases.compactMap { system in totals[system].map { (system, $0.0, $0.1) } }
    }
    var isNarrowed: Bool { !systems.isEmpty || !query.isEmpty || filter != .all }
    var heading: String {
        switch systems.count {
        case 0: return "All games"
        case 1: return systems.first!.name
        default: return "\(systems.count) consoles"
        }
    }

    // MARK: Selection

    func select(_ id: String, shift: Bool = false, command: Bool = false) {
        let ids = visible.map(\.id)
        guard let end = ids.firstIndex(of: id) else { return }
        if shift, let anchor = selectionAnchor, let start = ids.firstIndex(of: anchor) {
            let range = Set(ids[min(start, end)...max(start, end)])
            selectedIDs = command ? selectedIDs.union(range) : range
        } else if command {
            if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
            selectionAnchor = id
        } else {
            selectedIDs = [id]; selectionAnchor = id
        }
        selection = selectedIDs.contains(id) ? id : ids.first { selectedIDs.contains($0) }
    }
    func setListSelection(_ ids: Set<String>) {
        selectedIDs = ids
        if selection.map({ !ids.contains($0) }) ?? true { selection = visible.first { ids.contains($0.id) }?.id }
        selectionAnchor = selection
    }
    func selectAllShown() { setListSelection(Set(visible.map(\.id))) }
    func clearSelection() { setListSelection([]) }
    /// Hidden games leave the selection, so an action never touches something that is not on screen.
    func pruneSelection() {
        selectedIDs.formIntersection(Set(visible.map(\.id)))
        if selection.map({ !selectedIDs.contains($0) }) ?? true { selection = visible.first { selectedIDs.contains($0.id) }?.id }
        if selectionAnchor.map({ !selectedIDs.contains($0) }) ?? false { selectionAnchor = selection }
    }
    /// Sidebar click: one console, or Command-click to combine several.
    func choose(_ system: GameSystem?, adding: Bool = false) {
        guard let system else { systems = []; return }
        if adding {
            if systems.contains(system) { systems.remove(system) } else { systems.insert(system) }
        } else {
            systems = [system]
        }
    }

    // MARK: Scopes

    /// The most specific scope in play: selected games, else what is listed, else everything.
    var defaultScope: Scope { !selectedIDs.isEmpty ? .selection : isNarrowed ? .shown : .library }
    func ids(in scope: Scope) -> Set<String> {
        switch scope {
        case .selection: return selectedIDs
        case .shown: return Set(visible.map(\.id))
        case .library: return Set(games.map(\.id))
        }
    }
    func title(for scope: Scope) -> String {
        switch scope {
        case .selection: return "Get artwork for \(selectedIDs.count) selected \(selectedIDs.count == 1 ? "game" : "games")"
        case .shown:
            if query.isEmpty, filter == .all { return "Get artwork for \(systems.count == 1 ? systems.first!.name : "\(systems.count) consoles")" }
            return "Get artwork for \(visible.count) shown \(visible.count == 1 ? "game" : "games")"
        case .library: return "Get artwork for all games"
        }
    }
    /// Finds and saves artwork for a scope; with `save` off, previews are kept in memory for review.
    func run(_ scope: Scope, save: Bool = true) { process(ids: ids(in: scope), save: save) }
    func downloadAndSaveAll() { run(.library) }
    func getForSelected() { run(.selection) }
    func getArtwork(for system: GameSystem) { process(ids: Set(games.filter { $0.system == system }.map(\.id)), save: true) }
    func getArtwork(ids: Set<String>) { process(ids: ids, save: true) }

    // MARK: Scanning

    func chooseFolder(destination choosingDestination: Bool = false) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = choosingDestination ? "Choose the artwork destination (SD root for TWiLight Menu++)." : "Choose your Roms folder or an individual system folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if choosingDestination { destination = url; refreshExisting() }
        else { folder = url.path; Self.defaults.set(folder, forKey: "romFolder"); scan() }
    }
    func scan() {
        guard !busy else { return }
        busy = true; message = "Scanning \(folder)…"; progress = 0
        let root = URL(fileURLWithPath: folder)
        job = Task {
            do {
                games = try await Task.detached { try Library.scan(root) }.value
                ThumbnailCache.shared.removeAll()
                identities = [:]; selectedIDs = []; selection = nil; selectionAnchor = nil
                systems.formIntersection(Set(games.map(\.system)))
                refreshExisting()
                message = games.isEmpty ? "No games found in \(folder)." : "\(games.count) games on \(systemCounts.count) \(systemCounts.count == 1 ? "console" : "consoles"). \(saved) already have artwork."
            } catch { self.error = error.localizedDescription; message = "Scan failed." }
            busy = false
        }
    }
    /// Unsaved previews belong to the previous artwork type, so they are dropped before rechecking the card.
    func kindChanged() {
        for index in games.indices { games[index].artwork = nil; games[index].source = "" }
        refreshExisting()
    }
    /// Rechecks which games already have artwork where the current profile would write it.
    func refreshExisting() {
        let configuration = settings
        for index in games.indices {
            if let url = try? Library.existing(for: games[index].url, settings: configuration) {
                games[index].savedURL = url; games[index].status = .saved
                if games[index].source.isEmpty { games[index].source = "Existing artwork" }
            } else {
                games[index].savedURL = nil
                games[index].status = games[index].artwork == nil ? .missing : .ready
                if games[index].source == "Existing artwork" { games[index].source = "" }
            }
        }
    }

    // MARK: Finding and saving

    func download(ids: Set<String>? = nil) { process(ids: ids, save: false) }
    func save(ids: Set<String>? = nil) { process(ids: ids, find: false, save: true) }
    func stop() { job?.cancel() }

    /// Works through the games in `ids` that have no saved artwork: finds a cover for each, and saves it straight away,
    /// so stopping or losing the card keeps everything finished so far.
    private func process(ids: Set<String>?, find: Bool = true, save: Bool) {
        guard !busy else { return }
        let targets = games.filter { $0.savedURL == nil && (ids?.contains($0.id) ?? true) && (find ? (save || $0.artwork == nil) : $0.artwork != nil) }
        guard !targets.isEmpty else { message = ids == nil ? "Every game already has artwork." : "Those games already have artwork."; return }
        let configuration = settings
        var blocked = Set<String>(), twins = Set<String>()
        if save {
            // A missing destination affects every game alike, so say so once before starting.
            var outputs: [String: [String]] = [:]
            var failures = 0, firstFailure: String?
            for game in targets {
                do { outputs[try configuration.output(for: game.url).path.lowercased(), default: []].append(game.id) }
                catch { failures += 1; firstFailure = firstFailure ?? error.localizedDescription }
            }
            if failures == targets.count { self.error = firstFailure; return }
            // Two ROMs that would write the same file are skipped; the rest of the batch carries on.
            for (_, sharing) in outputs where sharing.count > 1 {
                let folders = Set(sharing.map { ($0 as NSString).deletingLastPathComponent })
                // The same game kept in two formats side by side (Game.zip and Game.7z) shares one cover: the first fetches it.
                if folders.count == 1 { twins.formUnion(sharing.dropFirst()) } else { blocked.formUnion(sharing) }
            }
        }
        busy = true; progress = 0
        let queue = targets.map(\.id).filter { !twins.contains($0) }
        let service = service
        let collisions = blocked
        job = Task {
            // A name list that failed to load earlier, or hit GitHub's hourly limit, gets another try with each batch.
            await service.retryIndexes()
            var done = 0
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                func enqueue() {
                    guard next < queue.count, !Task.isCancelled else { return }
                    let id = queue[next]; next += 1
                    group.addTask { await self.processOne(id, find: find, save: save, collides: collisions.contains(id)) }
                }
                for _ in 0..<parallelism { enqueue() }
                for await _ in group {
                    done += 1; progress = Double(done) / Double(queue.count)
                    enqueue()
                }
            }
            for index in games.indices where twins.contains(games[index].id) {
                guard let url = try? Library.existing(for: games[index].url, settings: configuration) else { continue }
                games[index].savedURL = url; games[index].status = .saved; games[index].artwork = nil; games[index].source = "Shares the cover of the same game beside it"
            }
            summarize(queue: queue, done: done, saved: save, stopped: Task.isCancelled)
            busy = false
        }
    }

    private func index(of id: String) -> Int? { games.firstIndex { $0.id == id } }

    private func processOne(_ original: String, find: Bool, save: Bool, collides: Bool) async {
        var id = original
        guard !Task.isCancelled, let index = index(of: id) else { return }
        if games[index].artwork == nil {
            guard find else { return }
            message = "Finding artwork · \(games[index].title)"
            id = await self.find(id)
        }
        // A preview whose save failed earlier (full card, name collision) is saved again from memory.
        guard save, !Task.isCancelled, let index = self.index(of: id), games[index].savedURL == nil, let data = games[index].artwork else { return }
        if collides {
            games[index].status = .saveFailed
            games[index].source = "Another ROM would export to the same filename. Use the per-ROM Imgs layout or export them separately."
            return
        }
        let rom = games[index].url, configuration = settings
        do {
            let output = try await Task.detached { try Library.save(data, rom: rom, settings: configuration) }.value
            guard let index = self.index(of: id) else { return }
            // The saved file is now the copy on show; the download no longer needs to stay in memory.
            games[index].savedURL = output; games[index].status = .saved; games[index].artwork = nil
        } catch {
            guard let index = self.index(of: id) else { return }
            games[index].status = .saveFailed; games[index].source = error.localizedDescription
        }
    }

    /// Looks one game's artwork up, renaming the ROM first when filename normalization is on. Returns the game's id, which a rename changes.
    private func find(_ id: String) async -> String {
        guard let index = index(of: id) else { return id }
        var lookup = games[index]
        let kind = kind, system = lookup.system
        if kind != .box, !kind.supports(system) {
            games[index].status = .notFound
            games[index].source = "\(kind.rawValue) artwork does not exist for \(system.name). Import an image instead."
            return id
        }
        games[index].status = .searching
        var newID = id
        do {
            var canonical: String?
            if normalizeFilenames && kind == .box {
                guard identities[id] == nil, profile != .retroarch else { throw ArtError.message("Disable filename normalization for RetroArch or imported playlists; their paths must remain unchanged.") }
                canonical = try await service.normalizedName(for: lookup)
                lookup.lookupName = canonical ?? lookup.lookupName
            }
            let found = try await service.artwork(for: lookup, kind: kind)
            guard let index = self.index(of: id) else { return id }
            guard let (data, source) = found else {
                games[index].status = .notFound
                games[index].source = await service.indexProblem(for: system) ?? "No artwork under this name. Import an image, or search online from the right-click menu."
                return id
            }
            // A ROM that cannot be renamed (its Libretro name is taken by another file, say) still gets its cover.
            var note = ""
            if let canonical {
                do { newID = try rename(index, to: canonical) }
                catch { try Task.checkCancellation(); note = " · Not renamed: \(error.localizedDescription)" }
            }
            try Task.checkCancellation()
            guard let index = self.index(of: newID) else { return newID }
            games[index].artwork = data; games[index].source = source + note; games[index].status = .ready
        } catch {
            guard let index = self.index(of: newID) else { return newID }
            if Task.isCancelled { games[index].status = .missing; return newID }
            games[index].status = .failed; games[index].source = error.localizedDescription
        }
        return newID
    }

    /// Renames a ROM to its Libretro name and carries the selection across to its new id.
    private func rename(_ index: Int, to canonical: String) throws -> String {
        let oldID = games[index].id, url = games[index].url
        if (try? Library.existing(for: url, settings: settings)) != nil { throw ArtError.message("Renaming skipped because this ROM already has artwork.") }
        let target = url.deletingLastPathComponent().appendingPathComponent(canonical).appendingPathExtension(url.pathExtension)
        if target != url, (try? Library.existing(for: target, settings: settings)) != nil { throw ArtError.message("Renaming skipped because the new name already has artwork.") }
        try Task.checkCancellation()
        let renamed = try FilenameNormalization.rename(url, to: canonical)
        games[index].url = renamed; games[index].title = Game.clean(canonical); games[index].lookupName = canonical
        if selectedIDs.remove(oldID) != nil { selectedIDs.insert(renamed.path) }
        if selection == oldID { selection = renamed.path }
        if selectionAnchor == oldID { selectionAnchor = renamed.path }
        return renamed.path
    }

    private func summarize(queue: [String], done: Int, saved save: Bool, stopped: Bool) {
        let ids = Set(queue)
        // Renamed games changed id, so count by what is left rather than by the original list.
        let touched = games.filter { ids.contains($0.id) }
        var parts: [String] = []
        let savedCount = touched.filter { $0.status == .saved }.count + (queue.count - touched.count)
        let readyCount = touched.filter { $0.status == .ready }.count
        let notFound = touched.filter { $0.status == .notFound }.count
        let failed = touched.filter { $0.status == .failed || $0.status == .saveFailed }.count
        if save { parts.append("Saved \(savedCount) of \(queue.count)") }
        if readyCount > 0 { parts.append("\(readyCount) ready to save") }
        if notFound > 0 { parts.append("\(notFound) not found") }
        if failed > 0 { parts.append("\(failed) failed") }
        message = (stopped ? "Stopped. " : "") + parts.joined(separator: " · ") + "."
    }

    // MARK: Single-game actions

    func importPlaylists() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Choose RetroArch JSON .lpl playlists. Entries are matched to ROMs by unique filename, even when device paths differ."
        guard panel.runModal() == .OK else { return }
        do {
            var matches = identities
            for url in panel.urls {
                let imported = try Playlist.match(data: Data(contentsOf: url), playlistName: url.lastPathComponent, games: games)
                matches.merge(imported) { _, new in new }
            }
            identities = matches
            for i in games.indices { games[i].lookupName = identities[games[i].id]?.label }
            refreshExisting(); message = "Matched playlist labels to \(matches.count) games. Ambiguous or absent filenames were skipped."
        } catch { self.error = error.localizedDescription }
    }
    func importImage(for id: String? = nil) {
        guard !busy, let index = games.firstIndex(where: { $0.id == (id ?? selection) }), games[index].savedURL == nil else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .webP]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            _ = try Library.render(data, settings: settings)
            games[index].artwork = data; games[index].source = "Imported · \(url.lastPathComponent)"; games[index].status = .ready
        } catch { self.error = error.localizedDescription }
    }
    /// Moves a game's saved artwork to the Trash, so a wrong cover can be found again or replaced by an import.
    func removeArtwork(for ids: Set<String>) {
        guard !busy else { return }
        var removed = 0
        for index in games.indices where ids.contains(games[index].id) {
            guard let url = games[index].savedURL else { continue }
            do {
                try Library.removeArtwork(at: url)
                ThumbnailCache.shared.remove(CoverView.key(for: games[index]))
                games[index].savedURL = nil; games[index].artwork = nil; games[index].status = .missing; games[index].source = ""
                removed += 1
            } catch { self.error = error.localizedDescription; break }
        }
        if removed > 0 { message = "Moved \(removed) \(removed == 1 ? "cover" : "covers") to the Trash." }
    }
}
