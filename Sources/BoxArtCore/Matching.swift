import Foundation

/// The artwork names one Libretro thumbnail set holds, indexed for lookup.
public struct ArtworkIndex: Sendable {
    public let names: [String]
    private let exact: Set<String>
    private let byKey: [String: [String]]

    public init(names: [String]) {
        self.names = names
        exact = Set(names)
        var keys: [String: [String]] = [:]
        for name in names {
            for key in ArtworkMatcher.keys(for: name, reduced: false) { keys[key, default: []].append(name) }
        }
        byKey = keys
    }
    public func contains(_ name: String) -> Bool { exact.contains(name) }
    func candidates(for key: String) -> [String] { byKey[key] ?? [] }
}

/// Finds the artwork for a ROM filename without ever crossing to a different title.
///
/// A name matches when it is identical, or when it is the same title once region, revision, language and
/// dump tags are set aside. Among several releases of that title the ROM's own region wins, then USA, World,
/// Europe and Japan. Sequels and editions keep distinct titles, so "Mega Man 2" never takes "Mega Man 3".
public enum ArtworkMatcher {
    public struct Match: Equatable, Sendable {
        public let name: String
        public let exact: Bool
    }

    public static func match(_ stem: String, in index: ArtworkIndex) -> Match? {
        let safe = PlaylistIdentity.safeName(stem)
        if index.contains(safe) { return Match(name: safe, exact: true) }
        let regions = regions(in: stem)
        let ownTags = Set(tags(in: stem).map { $0.lowercased() })
        // Full titles first, so "Daytona USA" is not cut down to "Daytona" while an exact title exists.
        for reduced in [false, true] {
            var seen = Set<String>(), found: [String] = []
            for key in keys(for: stem, reduced: reduced) {
                for name in index.candidates(for: key) where seen.insert(name).inserted { found.append(name) }
            }
            var ranked: [(name: String, score: Int)] = []
            for name in found {
                if let score = score(name, regions: regions, ownTags: ownTags) { ranked.append((name, score)) }
            }
            ranked.sort { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.name.count != b.name.count { return a.name.count < b.name.count }
                return a.name < b.name
            }
            if let best = ranked.first { return Match(name: best.name, exact: false) }
        }
        return nil
    }

    /// The parenthesised and bracketed tags of a name: `(USA)`, `(Rev 1)`, `[T-En by …]`.
    static func tags(in name: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"\(([^)]*)\)|\[([^\]]*)\]"#)
        let text = name as NSString
        return pattern.matches(in: name, range: NSRange(location: 0, length: text.length)).map {
            text.substring(with: $0.range(at: $0.range(at: 1).location != NSNotFound ? 1 : 2))
        }
    }

    private static let regionNames: [String: String] = [
        "usa": "USA", "u": "USA", "us": "USA", "america": "USA",
        "europe": "Europe", "e": "Europe", "eu": "Europe", "eur": "Europe", "uk": "Europe", "france": "Europe", "germany": "Europe", "spain": "Europe", "italy": "Europe",
        "japan": "Japan", "j": "Japan", "jp": "Japan", "jpn": "Japan", "jap": "Japan",
        "world": "World", "w": "World",
    ]

    /// Regions named by No-Intro tags `(USA, Europe)`, scene tags `(U)`, `[EUR]`, or bare tokens in scene names.
    public static func regions(in name: String) -> Set<String> {
        var result = Set<String>()
        for tag in tags(in: name) {
            for part in tag.components(separatedBy: ",") {
                if let region = regionNames[part.trimmingCharacters(in: .whitespaces).lowercased()] { result.insert(region) }
            }
        }
        if result.isEmpty {
            let bare = name.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
            for token in bare.components(separatedBy: CharacterSet.alphanumerics.inverted) where ["USA", "EUR", "JPN", "JAP"].contains(token) {
                result.insert(regionNames[token.lowercased()]!)
            }
        }
        return result
    }

    private static let unfinished = ["beta", "proto", "demo", "sample", "kiosk", "pirate", "possible proto"]

    /// Ranks one candidate release against the ROM, or rejects it.
    private static func score(_ candidate: String, regions: Set<String>, ownTags: Set<String>) -> Int? {
        let candidateTags = tags(in: candidate)
        let lowered = candidateTags.map { $0.lowercased() }
        // Prototypes and demos have their own artwork; only a prototype ROM should get it.
        for word in unfinished where lowered.contains(where: { $0 == word || $0.hasPrefix(word + " ") }) {
            guard ownTags.contains(where: { $0 == word || $0.hasPrefix(word + " ") }) else { return nil }
        }
        var score = 0
        let candidateRegions = Self.regions(in: candidate)
        if !candidateRegions.isEmpty { score += 20 }
        if !regions.isDisjoint(with: candidateRegions) { score += 100 }
        let preference: [(String, Int)] = [("USA", 40), ("World", 35), ("Europe", 30), ("Japan", 10)]
        if let preferred = preference.first(where: { candidateRegions.contains($0.0) }) { score += preferred.1 }
        for tag in lowered {
            if ownTags.contains(tag) { score += 5 }
            else if isPatch(tag) { score -= 15 }
            else if tag.hasPrefix("rev ") || tag.hasPrefix("v") || tag.contains("collection") { score -= 4 }
            else if tag.hasPrefix("disc ") { if tag != "disc 1" { score -= 2 } }
            else if Self.regions(in: "(\(tag))").isEmpty { score -= 1 }
        }
        return score
    }

    /// Translation and hack markers: `[T-En by …]`, `[tr en …]`, `[h …]`.
    private static func isPatch(_ tag: String) -> Bool {
        tag.hasPrefix("t-") || tag.hasPrefix("tr ") || tag.hasPrefix("h ") || tag.contains("hack")
    }

    /// Comparison keys for a name: the title alone, lowercased, without punctuation, articles or tags.
    /// `reduced` also drops the version numbers, release-group names and loose region words of scene and hack names.
    static func keys(for name: String, reduced: Bool) -> [String] {
        var value = stripROMExtension(name)
        value = value.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[_&]"#, with: " ", options: .regularExpression)
        if reduced {
            let before = value
            // Only when nothing but more such tags follows: "Daytona USA 2" keeps its name.
            value = value.replacingOccurrences(of: #"(?<=\S)\s+(?:USA|EUR|JPN|JAP|EN|NDS|PSP|GBA|MULTi\d*|PROPER|READNFO)(?:[\s-]+[A-Z][A-Za-z0-9]*)*\s*$"#, with: "", options: .regularExpression)
            value = value.replacingOccurrences(of: #"(?i)(?<=\S)\s+(?:v\d[\w.]*|english|translated|patched|hack)\b.*$"#, with: "", options: .regularExpression)
            guard value != before else { return [] }
        }
        // "Lock n' Chase ~ Lock 'n' Chase" lists alternative titles; either may be the artwork's name.
        let parts = value.components(separatedBy: " ~ ")
        var result: [String] = []
        for part in (parts.count > 1 ? [value] + parts : [value]) {
            var text = part.replacingOccurrences(of: #"(?i),\s*(?:the|a|an)\b"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?i)^\s*the\s+"#, with: "", options: .regularExpression)
            let key = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().filter { $0.isLetter || $0.isNumber }
            if !key.isEmpty, !result.contains(key) { result.append(key) }
        }
        return result
    }

    /// "Tetris DX (World).gbc" as the stem of "Tetris DX (World).gbc.zip" still names a Game Boy Color game.
    public static func stripROMExtension(_ stem: String) -> String {
        let ext = (stem as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, ext.count <= 4, GameSystem.allCases.contains(where: { $0.extensions.contains(ext) }) else { return stem }
        return (stem as NSString).deletingPathExtension
    }
}

/// Arcade ROM sets are named by short codes. This reads the title for each from a ClrMamePro DAT:
/// `game ( name "Metal Slug - Super Vehicle-001" … rom ( name mslug.zip …`.
public enum ArcadeTitles {
    public static func parse(_ dat: String) -> [String: String] {
        var titles: [String: String] = [:]
        var current: String?
        for line in dat.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("name \""), text.hasSuffix("\"") {
                current = String(text.dropFirst(6).dropLast())
            } else if text.hasPrefix("rom ( name "), let title = current {
                var file = text.dropFirst(11)
                if file.hasPrefix("\"") { file = file.dropFirst(); file = file.prefix { $0 != "\"" } }
                else { file = file.prefix { $0 != " " } }
                let short = (String(file) as NSString).deletingPathExtension.lowercased()
                if !short.isEmpty, titles[short] == nil { titles[short] = title }
                current = nil
            }
        }
        return titles
    }
}
