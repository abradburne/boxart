import Foundation

/// A console, computer or arcade platform. The raw value is the Libretro database name, which is also the
/// RetroArch thumbnail folder and (with underscores) the libretro-thumbnails repository.
public enum GameSystem: String, CaseIterable, Identifiable, Sendable {
    // Nintendo
    case nds = "Nintendo - Nintendo DS"
    case gba = "Nintendo - Game Boy Advance"
    case gb = "Nintendo - Game Boy"
    case gbc = "Nintendo - Game Boy Color"
    case nes = "Nintendo - Nintendo Entertainment System"
    case fds = "Nintendo - Family Computer Disk System"
    case snes = "Nintendo - Super Nintendo Entertainment System"
    case n64 = "Nintendo - Nintendo 64"
    case virtualBoy = "Nintendo - Virtual Boy"
    case pokemonMini = "Nintendo - Pokemon Mini"
    case gameAndWatch = "Handheld Electronic Game"
    // Sony
    case ps = "Sony - PlayStation"
    case psp = "Sony - PlayStation Portable"
    // Sega
    case genesis = "Sega - Mega Drive - Genesis"
    case sms = "Sega - Master System - Mark III"
    case gg = "Sega - Game Gear"
    case sg1000 = "Sega - SG-1000"
    case segacd = "Sega - Mega-CD - Sega CD"
    case sega32x = "Sega - 32X"
    case saturn = "Sega - Saturn"
    case dreamcast = "Sega - Dreamcast"
    case naomi = "Sega - Naomi"
    case atomiswave = "Atomiswave"
    // NEC
    case pce = "NEC - PC Engine - TurboGrafx 16"
    case pcecd = "NEC - PC Engine CD - TurboGrafx-CD"
    case supergrafx = "NEC - PC Engine SuperGrafx"
    // Atari
    case atari = "Atari - 2600"
    case atari5200 = "Atari - 5200"
    case atari7800 = "Atari - 7800"
    case atari8bit = "Atari - 8-bit Family"
    case atariST = "Atari - ST"
    case lynx = "Atari - Lynx"
    case jaguar = "Atari - Jaguar"
    // SNK, Bandai
    case ngp = "SNK - Neo Geo Pocket"
    case ngpc = "SNK - Neo Geo Pocket Color"
    case neogeo = "SNK - Neo Geo"
    case neogeoCD = "SNK - Neo Geo CD"
    case ws = "Bandai - WonderSwan"
    case wsc = "Bandai - WonderSwan Color"
    // Arcade
    case fbneo = "FBNeo - Arcade Games"
    case mame = "MAME"
    // Computers and others
    case amiga = "Commodore - Amiga"
    case c64 = "Commodore - 64"
    case vic20 = "Commodore - VIC-20"
    case msx = "Microsoft - MSX"
    case msx2 = "Microsoft - MSX2"
    case dos = "DOS"
    case scummvm = "ScummVM"
    case coleco = "Coleco - ColecoVision"
    case intellivision = "Mattel - Intellivision"
    case vectrex = "GCE - Vectrex"
    case zxSpectrum = "Sinclair - ZX Spectrum"
    case amstradCPC = "Amstrad - CPC"
    case supervision = "Watara - Supervision"

    public var id: String { rawValue }
    public var repository: String { rawValue.replacingOccurrences(of: " ", with: "_") }

    /// A short name for sidebars and buttons.
    public var name: String {
        switch self {
        case .nds: return "Nintendo DS"
        case .nes: return "NES"
        case .fds: return "Famicom Disk System"
        case .snes: return "Super Nintendo"
        case .gameAndWatch: return "Game & Watch"
        case .genesis: return "Mega Drive · Genesis"
        case .sms: return "Master System"
        case .segacd: return "Mega-CD · Sega CD"
        case .pce: return "PC Engine · TurboGrafx-16"
        case .pcecd: return "PC Engine CD"
        case .supergrafx: return "SuperGrafx"
        case .atari8bit: return "Atari 8-bit"
        case .fbneo: return "Arcade"
        case .mame: return "MAME"
        case .atomiswave, .dos, .scummvm: return rawValue
        default:
            let parts = rawValue.components(separatedBy: " - ")
            let rest = parts.dropFirst().joined(separator: " · ")
            // "Atari - 2600" reads better with its maker; "Nintendo - Game Boy" does not need it.
            return rest.first?.isNumber == true || ["Amiga", "ST", "CPC"].contains(rest) ? parts.joined(separator: " ") : rest
        }
    }

    /// ROM folder names used by Anbernic stock firmware, dslot, muOS, Knulli, ArkOS and EmulationStation. Matched case-insensitively.
    var folders: [String] {
        switch self {
        case .nds: return ["NDS"]
        case .gba: return ["GBA"]
        case .gb: return ["GB"]
        case .gbc: return ["GBC"]
        case .nes: return ["FC", "NES", "FAMICOM"]
        case .fds: return ["FDS"]
        case .snes: return ["SFC", "SNES", "SUPERFAMICOM"]
        case .n64: return ["N64"]
        case .virtualBoy: return ["VB", "VIRTUALBOY"]
        case .pokemonMini: return ["POKE", "POKEMINI"]
        case .gameAndWatch: return ["GW", "GAMEANDWATCH"]
        case .ps: return ["PS", "PS1", "PSX", "PLAYSTATION"]
        case .psp: return ["PSP"]
        case .genesis: return ["MD", "GENESIS", "MEGADRIVE"]
        case .sms: return ["SMS", "MASTERSYSTEM"]
        case .gg: return ["GG", "GAMEGEAR"]
        case .sg1000: return ["SG1000", "SG-1000"]
        case .segacd: return ["MDCD", "SEGACD", "MEGACD"]
        case .sega32x: return ["32X", "SEGA32X"]
        case .saturn: return ["SATURN"]
        case .dreamcast: return ["DREAMCAST"]
        case .naomi: return ["NAOMI"]
        case .atomiswave: return ["ATOMISWAVE"]
        case .pce: return ["PCE", "PCENGINE", "TG16"]
        case .pcecd: return ["PCECD", "PCENGINECD", "TGCD"]
        case .supergrafx: return ["SGFX", "SGX", "SUPERGRAFX"]
        case .atari: return ["A2600", "ATARI2600", "ATARI"]
        case .atari5200: return ["A5200", "ATARI5200"]
        case .atari7800: return ["A7800", "ATARI7800"]
        case .atari8bit: return ["A800", "ATARI800"]
        case .atariST: return ["ATARIST"]
        case .lynx: return ["LYNX"]
        case .jaguar: return ["JAGUAR"]
        case .ngp: return ["NGP"]
        case .ngpc: return ["NGPC"]
        case .neogeo: return ["NEOGEO"]
        case .neogeoCD: return ["NEOCD", "NEOGEOCD"]
        case .ws: return ["WS", "WONDERSWAN"]
        case .wsc: return ["WSC", "WONDERSWANCOLOR"]
        case .fbneo: return ["ARCADE", "FBNEO", "FBA", "CPS1", "CPS2", "CPS3", "PGM", "PGM2", "VARCADE"]
        case .mame: return ["MAME"]
        case .amiga: return ["AMIGA"]
        case .c64: return ["C64"]
        case .vic20: return ["VIC20"]
        case .msx: return ["MSX"]
        case .msx2: return ["MSX2"]
        case .dos: return ["DOS"]
        case .scummvm: return ["SCUMMVM"]
        case .coleco: return ["COLECO", "COLECOVISION"]
        case .intellivision: return ["INTELLIVISION"]
        case .vectrex: return ["VECTREX"]
        case .zxSpectrum: return ["ZXS", "ZXSPECTRUM", "SPECTRUM"]
        case .amstradCPC: return ["CPC", "AMSTRADCPC"]
        case .supervision: return ["SUPERVISION"]
        }
    }

    /// Extensions that identify this system on their own, wherever the file sits.
    var extensions: [String] {
        switch self {
        case .nds: return ["nds", "dsi"]
        case .gba: return ["gba"]
        case .gb: return ["gb"]
        case .gbc: return ["gbc"]
        case .nes: return ["nes"]
        case .fds: return ["fds"]
        case .snes: return ["sfc", "smc"]
        case .n64: return ["z64", "n64", "v64"]
        case .virtualBoy: return ["vb"]
        case .genesis: return ["gen", "smd"]
        case .sms: return ["sms"]
        case .gg: return ["gg"]
        case .sega32x: return ["32x"]
        case .pce: return ["pce"]
        case .supergrafx: return ["sgx"]
        case .atari: return ["a26"]
        case .atari5200: return ["a52"]
        case .atari7800: return ["a78"]
        case .lynx: return ["lnx"]
        case .jaguar: return ["j64", "jag"]
        case .ngp: return ["ngp"]
        case .ngpc: return ["ngc"]
        case .ws: return ["ws"]
        case .wsc: return ["wsc"]
        case .vectrex: return ["vec"]
        default: return []
        }
    }

    /// Extensions accepted only inside one of this system's folders, because other things use them too
    /// (`README.md`, firmware `.bin` files, disk images shared between computers).
    var folderOnlyExtensions: [String] {
        switch self {
        case .genesis: return ["md"]
        case .sg1000: return ["sg"]
        case .pokemonMini: return ["min"]
        case .coleco: return ["col"]
        case .intellivision: return ["int"]
        case .supervision: return ["sv"]
        case .atari: return ["bin"]
        case .atari8bit: return ["atr", "xex", "xfd", "cas", "car"]
        case .atariST: return ["st", "stx", "msa", "ipf"]
        case .amiga: return ["adf", "ipf", "lha", "hdf", "adz", "dms"]
        case .c64, .vic20: return ["d64", "t64", "prg", "crt", "tap", "g64", "d81"]
        case .msx, .msx2: return ["mx1", "mx2", "dsk", "cas"]
        case .zxSpectrum: return ["tzx", "tap", "z80", "sna", "dsk"]
        case .amstradCPC: return ["dsk", "sna", "cdt"]
        case .gameAndWatch: return ["mgw"]
        case .dos: return ["dosz", "exe", "conf"]
        case .scummvm: return ["scummvm"]
        case .naomi, .atomiswave: return ["lst", "dat"]
        default: return []
        }
    }

    /// Systems whose artwork sets overlap: a `.gb` file in a GBC folder, or a compatible re-release.
    public var siblings: [GameSystem] {
        switch self {
        case .gb: return [.gbc]
        case .gbc: return [.gb]
        case .ngp: return [.ngpc]
        case .ngpc: return [.ngp]
        case .ws: return [.wsc]
        case .wsc: return [.ws]
        case .sms: return [.sg1000]
        case .sg1000: return [.sms]
        case .pce: return [.supergrafx]
        case .supergrafx: return [.pce]
        case .msx: return [.msx2]
        case .msx2: return [.msx]
        case .nes: return [.fds]
        case .fbneo: return [.mame, .neogeo]
        case .mame: return [.fbneo]
        case .neogeo: return [.fbneo]
        case .naomi, .atomiswave: return [.mame]
        default: return []
        }
    }

    /// Arcade ROM sets are named by short codes (`mslug.zip`), which need a title database before artwork can be found.
    public var usesShortNames: Bool { [.fbneo, .mame, .neogeo, .naomi, .atomiswave].contains(self) }

    /// Archive and disc containers that say nothing about the system inside.
    static let containers: Set<String> = ["zip", "7z", "chd", "cue", "pbp", "iso", "cso", "m3u", "bin", "gdi", "rom", "ccd", "img", "cdi", "rvz"]

    /// Folders that hold artwork, saves, ports and other support files rather than ROMs. Nothing inside them is scanned.
    public static let supportFolders: Set<String> = ["imgs", "labels", "carts", "artwork", "images", "media", "boxart", "covers", "manuals", "saves", "states", "bios", "cheats", "samples", "ports", "apps"]

    private static let byFolder: [String: GameSystem] = {
        var map: [String: GameSystem] = [:]
        for system in allCases {
            for folder in system.folders { map[folder] = system }
            map[system.rawValue.uppercased()] = system
        }
        return map
    }()
    private static let byExtension: [String: GameSystem] = {
        var map: [String: GameSystem] = [:]
        for system in allCases { for ext in system.extensions { map[ext] = system } }
        return map
    }()

    /// The system of the nearest enclosing folder with a known name.
    public static func folderSystem(_ url: URL) -> GameSystem? {
        for part in url.deletingLastPathComponent().pathComponents.reversed() {
            if let system = byFolder[part.uppercased()] { return system }
        }
        return nil
    }

    /// Identifies a ROM by its extension and enclosing system folder. Returns nil for anything that is not a game.
    public static func infer(_ url: URL) -> GameSystem? {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        let folder = folderSystem(url)
        if let own = byExtension[ext] {
            // A `.gb` file in a GBC folder stays in the GBC list; a `.gba` file in an NDS folder is still a GBA game.
            if let folder, folder != own, folder.siblings.contains(own) { return folder }
            return own
        }
        guard let folder else { return nil }
        if containers.contains(ext) || folder.folderOnlyExtensions.contains(ext) { return folder }
        return nil
    }
}

public struct PlaylistIdentity: Sendable {
    public let label: String
    public let database: String
    public init(label: String, database: String) { self.label = label; self.database = database }
    /// Libretro replaces these characters in thumbnail filenames.
    public static func safeName(_ text: String) -> String {
        text.replacingOccurrences(of: #"[&*/:`<>?\\|\"]"#, with: "_", options: .regularExpression)
    }
}

public enum Playlist {
    struct Document: Decodable { let items: [Item] }
    struct Item: Decodable { let path: String; let label: String; let db_name: String? }
    public static func match(data: Data, playlistName: String, games: [Game]) throws -> [String: PlaylistIdentity] {
        let doc = try JSONDecoder().decode(Document.self, from: data)
        var result: [String: PlaylistIdentity] = [:]
        for item in doc.items {
            let path = item.path.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "#")[0]
            let name = (path as NSString).lastPathComponent
            let matches = games.filter { $0.url.lastPathComponent == name }
            guard matches.count == 1, let game = matches.first else { continue }
            let database = (item.db_name?.isEmpty == false ? item.db_name! : playlistName) as NSString
            let identity = PlaylistIdentity(label: item.label, database: database.deletingPathExtension)
            guard !identity.label.isEmpty, !identity.database.isEmpty, identity.database != ".", identity.database != "..", !identity.database.contains("/"), !identity.database.contains("\\") else { throw ArtError.message("Playlist contains an invalid thumbnail name.") }
            if let previous = result[game.id], previous.label != identity.label || previous.database != identity.database { throw ArtError.message("Playlist contains conflicting entries for \(name).") }
            result[game.id] = identity
        }
        return result
    }
}
