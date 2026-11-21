import Foundation
import ImageIO

/// Looks artwork up online. Nothing here writes to the ROM library.
public actor ArtworkService {
    private let session: URLSession
    private let cache: URL

    public init(cacheDirectory: URL? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = ["User-Agent": "BoxArt-macOS/1.0"]
        session = URLSession(configuration: config)
        cache = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("BoxArt", isDirectory: true)
    }

    private func fetch(_ url: URL, hops: Int = 3) async throws -> Data? {
        try Task.checkCancellation()
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else { throw ArtError.message("Invalid server response.") }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw ArtError.message("Artwork server returned HTTP \(response.statusCode). Try again later.") }
        if Self.isImage(data) { return data }
        // Libretro keeps one file per cover and links the other revisions and translations to it.
        guard hops > 0, let target = Self.linkTarget(data), let next = URL(string: target, relativeTo: url) else { return nil }
        return try await fetch(next.absoluteURL, hops: hops - 1)
    }

    /// True only for data that decodes to at least one image. A non-nil image source alone proves nothing.
    static func isImage(_ data: Data) -> Bool {
        guard data.count < 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetStatus(source) == .statusComplete
    }

    /// A git symbolic link served as a file: its whole content is the relative path of the real image.
    static func linkTarget(_ data: Data) -> String? {
        guard data.count < 1024, let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.contains("\n"), !text.hasPrefix("/"), !text.contains("://"),
              ["png", "jpg", "jpeg"].contains((text as NSString).pathExtension.lowercased()) else { return nil }
        return text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    // MARK: Cached lists

    /// A downloaded list kept on disk so that a library is not re-indexed on every run.
    private func cached(_ file: String, maxAge: TimeInterval, download: () async throws -> Data) async -> Data? {
        let url = cache.appendingPathComponent(file)
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let modified, Date().timeIntervalSince(modified) < maxAge, let data = try? Data(contentsOf: url) { return data }
        if let data = try? await download() {
            try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            return data
        }
        // A stale list is better than none when the server is unreachable or rate-limited.
        return try? Data(contentsOf: url)
    }

    // MARK: Libretro name indexes

    private var indexes: [GameSystem: ArtworkIndex] = [:]
    private var indexTasks: [GameSystem: Task<ArtworkIndex?, Never>] = [:]
    private var indexProblems: [GameSystem: String] = [:]

    /// Why title matching was unavailable for a system, if it was.
    public func indexProblem(for system: GameSystem) -> String? { indexProblems[system] }

    /// Forgets earlier failures so the next lookups try the name lists again.
    public func retryIndexes() { indexProblems = [:] }

    /// Every box-art name Libretro holds for a system: one request per system, cached for two weeks.
    public func index(for system: GameSystem) async -> ArtworkIndex? {
        if let index = indexes[system] { return index }
        if indexProblems[system] != nil { return nil }
        if let running = indexTasks[system] { return await running.value }
        let task = Task { await self.loadIndex(system) }
        indexTasks[system] = task
        let index = await task.value
        indexTasks[system] = nil
        return index
    }

    private func loadIndex(_ system: GameSystem) async -> ArtworkIndex? {
        var problem = "Libretro’s name list for \(system.name) is unavailable, so only the exact filename was tried."
        let data = await cached("names-\(system.repository).txt", maxAge: 14 * 86_400) {
            struct Tree: Decodable { struct Entry: Decodable { let path: String; let type: String }; let tree: [Entry]; let truncated: Bool? }
            // The Named_Boxarts subtree alone: the whole repository is too large for one request on big systems.
            let url = URL(string: "https://api.github.com/repos/libretro-thumbnails/\(system.repository)/git/trees/master:Named_Boxarts")!
            let (data, response) = try await self.session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 403 || status == 429 { problem = "GitHub’s hourly limit for name lists was reached, so only the exact filename was tried. Try again in an hour." }
            guard status == 200 else { throw ArtError.message(problem) }
            let tree = try JSONDecoder().decode(Tree.self, from: data)
            guard tree.truncated != true else { throw ArtError.message(problem) }
            let names = tree.tree.filter { $0.type == "blob" && $0.path.hasSuffix(".png") }.map { String($0.path.dropLast(4)) }
            return Data(names.joined(separator: "\n").utf8)
        }
        guard let data, !data.isEmpty else { indexProblems[system] = problem; return nil }
        let index = ArtworkIndex(names: String(decoding: data, as: UTF8.self).components(separatedBy: "\n"))
        indexes[system] = index
        return index
    }

    private var arcadeTitles: [String: String]?
    /// Titles for arcade short names, from the FinalBurn Neo set list in the Libretro database.
    private func arcadeTitle(for shortName: String) async -> String? {
        if arcadeTitles == nil {
            let data = await cached("fbneo-titles.dat", maxAge: 30 * 86_400) {
                let url = URL(string: "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/fbneo-split/FBNeo%20-%20Arcade%20Games.dat")!
                let (data, response) = try await self.session.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ArtError.message("Arcade title list unavailable.") }
                return data
            }
            arcadeTitles = data.map { ArcadeTitles.parse(String(decoding: $0, as: UTF8.self)) } ?? [:]
        }
        return arcadeTitles?[shortName.lowercased()]
    }

    private var checksumTitles: [GameSystem: [String: String]] = [:]
    /// The No-Intro name of a dump, by checksum. A system without a list simply has none.
    private func checksumTitle(_ crc: String, system: GameSystem) async -> String? {
        if checksumTitles[system] == nil {
            let file = system.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? system.rawValue
            let data = await cached("no-intro-\(system.repository).dat", maxAge: 30 * 86_400) {
                let url = URL(string: "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/no-intro/\(file).dat")!
                let (data, response) = try await self.session.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ArtError.message("No checksum list for this system.") }
                return data
            }
            checksumTitles[system] = data.map { ChecksumTitles.parse(String(decoding: $0, as: UTF8.self)) } ?? [:]
        }
        return checksumTitles[system]?[crc]
    }

    // MARK: Filename normalization

    /// The Libretro name a ROM could be renamed to: its own name if that is already one, or the single unambiguous match.
    public func normalizedName(for game: Game) async throws -> String? {
        guard let index = await index(for: game.system) else { throw ArtError.message("Artwork name index unavailable; no automatic rename was made. Try again later.") }
        let original = game.url.deletingPathExtension().lastPathComponent
        if index.contains(original) { return original }
        return FilenameNormalization.match(original, names: index.names)
    }

    // MARK: Cart labels and carts

    private static func regions(for code: String) -> [String] {
        let region: String
        switch code.last { case "J": region = "JA"; case "K": region = "KO"; case "D": region = "DE"; case "F": region = "FR"; case "I": region = "IT"; case "S": region = "ES"; case "E": region = "US"; default: region = "EN" }
        var regions: [String] = []
        for value in [region, "US", "EN", "JA"] where !regions.contains(value) { regions.append(value) }
        return regions
    }

    private static let slotArt = URL(string: "https://art.slot-cfw.fyi/")!
    private var slotLabels: [String: String]?
    /// Game Boy, Game Boy Color and Game Boy Advance label scans from the slot CFW art set, keyed by the dump's CRC32.
    func slotLabel(crc: String) async throws -> (Data, String)? {
        if slotLabels == nil {
            struct Entry: Decodable { let texture: String?; enum CodingKeys: String, CodingKey { case texture = "support-texture" } }
            let (data, response) = try await session.data(from: Self.slotArt.appendingPathComponent("index.json"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ArtError.message("Cart label index unavailable. Try again later.") }
            slotLabels = try JSONDecoder().decode([String: Entry].self, from: data).compactMapValues(\.texture)
        }
        guard let path = slotLabels?[crc] else { return nil }
        // Listed but not served is an outage at the host, not a game without a label.
        guard let data = try await fetch(Self.slotArt.appendingPathComponent(path)) else { throw ArtError.message("The slot CFW art set lists this label but is not serving the image. Try again later.") }
        return (data, "slot CFW art · ScreenScraper · \(crc)")
    }

    /// DS labels and whole carts come from GameTDB by exact game code; GB, GBC and GBA labels by exact ROM checksum. There is no filename fallback.
    private func cartArtwork(for game: Game, kind: ArtKind) async throws -> (Data, String)? {
        if kind == .label, [.gb, .gbc, .gba].contains(game.system) {
            let rom = game.url
            guard let crc = try await Task.detached(operation: { try Library.gameBoyChecksum(rom) }).value else { return nil }
            return try await slotLabel(crc: crc)
        }
        guard let code = game.code else { return nil }
        let type = kind == .label ? "label" : "cart"
        for region in Self.regions(for: code) {
            let url = URL(string: "https://art.gametdb.com/ds/\(type)/\(region)/\(code).png")!
            if let data = try await fetch(url) { return (data, "GameTDB · \(code) · \(region) · \(type)") }
        }
        return nil
    }

    // MARK: Box art

    private func boxart(_ name: String, system: GameSystem) async throws -> Data? {
        let base = URL(string: "https://raw.githubusercontent.com/libretro-thumbnails/\(system.repository)/master/Named_Boxarts/")!
        return try await fetch(base.appendingPathComponent(name + ".png"))
    }

    /// Finds artwork for a game, most certain source first:
    /// the exact filename at Libretro, the DS game code at GameTDB, then the same title in Libretro's name list
    /// for the system and the systems that share its library.
    public func artwork(for game: Game, kind: ArtKind = .box) async throws -> (Data, String)? {
        if kind != .box { return try await cartArtwork(for: game, kind: kind) }
        var lastError: Error?
        var stem = game.lookupName ?? ArtworkMatcher.stripROMExtension(game.url.deletingPathExtension().lastPathComponent)
        if game.lookupName == nil, game.system.usesShortNames, let title = await arcadeTitle(for: stem) { stem = title }
        if game.lookupName == nil, game.system == .gameAndWatch, let cover = GameAndWatch.entry(for: stem)?.artwork { stem = cover }
        let safe = PlaylistIdentity.safeName(stem)

        // With the name list already in hand, a request for a name it lacks is known to fail.
        if indexes[game.system]?.contains(safe) ?? true {
            do { if let data = try await boxart(safe, system: game.system) { return (data, "Libretro · exact filename") } }
            catch { try Task.checkCancellation(); lastError = error }
        }
        if let code = game.code {
            let regions = Self.regions(for: code)
            for (cover, ext) in [("coverM", "jpg"), ("coverS", "png")] {
                for region in regions {
                    let url = URL(string: "https://art.gametdb.com/ds/\(cover)/\(region)/\(code).\(ext)")!
                    do { if let data = try await fetch(url) { return (data, "GameTDB · \(code) · \(region) · \(cover)") } }
                    catch { try Task.checkCancellation(); lastError = error; break }
                }
            }
        }
        // A misnamed but unmodified dump is identified by its checksum, which then names its artwork.
        if game.lookupName == nil, !game.system.usesShortNames, game.system != .gameAndWatch {
            let rom = game.url
            let crc = try? await Task.detached(operation: { try Library.romChecksum(rom) }).value
            for system in [game.system] + game.system.siblings {
                guard let crc, let name = await checksumTitle(crc, system: system) else { continue }
                do {
                    if let data = try await boxart(PlaylistIdentity.safeName(name), system: system) { return (data, "Libretro · ROM checksum \(crc) · \(name)") }
                } catch { try Task.checkCancellation(); lastError = error }
                // No cover under that exact release: look for the same title instead.
                stem = name
                break
            }
        }
        for system in [game.system] + game.system.siblings {
            guard let index = await index(for: system), let match = ArtworkMatcher.match(stem, in: index) else { continue }
            if match.exact && system == game.system { continue }
            do {
                if let data = try await boxart(match.name, system: system) {
                    let set = system == game.system ? "Libretro" : "Libretro · \(system.name)"
                    return (data, match.exact ? "\(set) · exact filename" : "\(set) · same title · \(match.name)")
                }
            } catch { try Task.checkCancellation(); lastError = error }
        }
        if let lastError { throw lastError }
        return nil
    }
}
