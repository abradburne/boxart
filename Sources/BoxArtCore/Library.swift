import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import zlib

public enum ArtError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
public enum Profile: String, CaseIterable, Identifiable {
    case anbernic = "Anbernic · Imgs / NNDDSS", retroarch = "RetroArch", twilight = "TWiLight Menu++", custom = "Custom folder"
    public var id: String { rawValue }
    public var detail: String {
        switch self {
        case .anbernic: return "Imgs beside each ROM • filename without .nds • PNG. Community-reported layout; 512 px was tested on RG DS Plus; size is configurable."
        case .retroarch: return "Choose RetroArch’s thumbnails directory. Uses system/Named_Boxarts/label.png. Import .lpl playlists to match their exact labels; otherwise uses standard system names and ROM stems."
        case .twilight: return "Select the SD card root as destination. Uses _nds/TWiLightMenu/boxart and the full ROM filename. PNG fitted within 128 × 115."
        case .custom: return "Choose a destination, size and format. Images use the ROM filename without its extension."
        }
    }
}
/// Which piece of a game's packaging is being collected.
public enum ArtKind: String, CaseIterable, Identifiable {
    case box = "Box art", label = "Cart label", cart = "Cart"
    public var id: String { rawValue }
    /// Folder beside the ROMs in the Anbernic layout.
    public var folder: String {
        switch self { case .box: return "Imgs"; case .label: return "Labels"; case .cart: return "Carts" }
    }
    /// Box art exists for every system; labels and carts only where a provider scans them.
    public func supports(_ system: GameSystem) -> Bool {
        switch self {
        case .box: return true
        case .label: return [.nds, .gb, .gbc, .gba].contains(system)
        case .cart: return system == .nds
        }
    }
    public var detail: String {
        switch self {
        case .box: return "The front of the case."
        case .label: return "The sticker alone. DS labels are 272 : 296 and transparent outside their outline, matched by game code. Game Boy, Game Boy Color and Game Boy Advance labels are scans matched by ROM checksum. Frontends that draw their own cart shell, such as dslot, place it on the plastic."
        case .cart: return "The whole cart front including its shell, 336 : 360, transparent outside the cart. Nintendo DS only, matched by game code."
        }
    }
}
public struct ExportSettings {
    public var profile: Profile = .anbernic
    public var kind: ArtKind = .box
    public var identities: [String: PlaylistIdentity] = [:]
    public var destination: URL?
    public var maxSize: Int = 512
    public var jpeg: Bool = false
    public init() {}
    public static func suggestedRetroArchDirectory(for romFolder: URL) -> URL {
        let parts = romFolder.standardizedFileURL.pathComponents
        let root: URL
        if let index = parts.firstIndex(where: { $0.caseInsensitiveCompare("Roms") == .orderedSame }) {
            root = URL(fileURLWithPath: NSString.path(withComponents: Array(parts.prefix(index))), isDirectory: true)
        } else if parts.count > 2 && parts[1] == "Volumes" {
            root = URL(fileURLWithPath: "/Volumes/" + parts[2], isDirectory: true)
        } else {
            root = romFolder.deletingLastPathComponent()
        }
        for suffix in ["RetroArch/thumbnails", "retroarch/thumbnails", ".config/retroarch/thumbnails"] {
            let candidate = root.appendingPathComponent(suffix, isDirectory: true)
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &directory), directory.boolValue { return candidate }
        }
        return root.appendingPathComponent("RetroArch/thumbnails", isDirectory: true)
    }
    public func output(for rom: URL) throws -> URL {
        let folder: URL
        switch profile {
        case .anbernic: folder = rom.deletingLastPathComponent().appendingPathComponent(kind.folder, isDirectory: true)
        case .retroarch:
            guard kind == .box else { throw ArtError.message("RetroArch has no thumbnail type for cart artwork. Use the Anbernic or Custom folder profile.") }
            guard let destination else { throw ArtError.message("Choose RetroArch’s thumbnails directory.") }
            let identity = identities[rom.path]
            guard let system = identity?.database ?? GameSystem.infer(rom)?.rawValue else { throw ArtError.message("Cannot determine this ROM’s system.") }
            let name = PlaylistIdentity.safeName(identity?.label ?? rom.deletingPathExtension().lastPathComponent)
            return destination.appendingPathComponent(system, isDirectory: true).appendingPathComponent("Named_Boxarts", isDirectory: true).appendingPathComponent(name + ".png")
        case .twilight:
            guard kind == .box else { throw ArtError.message("TWiLight Menu++ shows box art only. Use the Anbernic or Custom folder profile.") }
            guard let destination else { throw ArtError.message("Choose the SD card root for TWiLight Menu++.") }
            folder = destination.appendingPathComponent("_nds/TWiLightMenu/boxart", isDirectory: true)
        case .custom:
            guard let destination else { throw ArtError.message("Choose an artwork destination.") }
            folder = destination
        }
        let name = profile == .twilight ? rom.lastPathComponent : rom.deletingPathExtension().lastPathComponent
        return folder.appendingPathComponent(name).appendingPathExtension(writesJPEG ? "jpg" : "png")
    }
    /// Cart artwork keeps its transparency, so it is always PNG.
    public var writesJPEG: Bool { profile == .custom && jpeg && kind == .box }
}
/// Where a game's artwork stands for the artwork type and export profile in use.
public enum ArtStatus: String, Sendable {
    case missing = "Missing", searching = "Searching", ready = "Ready", saved = "Saved"
    case notFound = "Not found", failed = "Error", saveFailed = "Save failed"
}
public struct Game: Identifiable, Sendable {
    public var url: URL
    public var id: String { url.path }
    public let system: GameSystem
    public var lookupName: String?
    public let code: String?
    public var title: String
    /// An unsaved preview held in memory. Saved artwork is read from `savedURL` when shown.
    public var artwork: Data?
    public var source: String = ""
    public var status: ArtStatus = .missing
    public var savedURL: URL?
    public init(url: URL, code: String?, system: GameSystem? = nil) {
        self.url = url; self.code = code
        self.system = system ?? GameSystem.infer(url) ?? .nds
        self.title = Self.clean(url.deletingPathExtension().lastPathComponent)
    }
    public static func clean(_ name: String) -> String {
        let title = ArtworkMatcher.stripROMExtension(name)
            .replacingOccurrences(of: #"\([^)]*\)|\[[^]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? name : title
    }
}
public enum Library {
    public static func gameCode(_ url: URL) throws -> String? {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        try file.seek(toOffset: 12)
        guard let bytes = try file.read(upToCount: 4), bytes.count == 4,
              bytes.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else { return nil }
        return String(data: bytes, encoding: .ascii)
    }
    /// CRC32 of the whole file, as No-Intro lists Game Boy and Game Boy Advance dumps.
    public static func crc32(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var crc = zlib.crc32(0, nil, 0)
        while let chunk = try file.read(upToCount: 1 << 20), !chunk.isEmpty {
            crc = chunk.withUnsafeBytes { zlib.crc32(crc, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
        }
        return String(format: "%08X", crc)
    }
    /// The checksum of a Game Boy family dump, loose or as the only such ROM in a ZIP. ZIPs store each entry's CRC32 in their central directory, so nothing is decompressed.
    public static func gameBoyChecksum(_ url: URL) throws -> String? {
        switch url.pathExtension.lowercased() {
        case "gb", "gbc", "gba": return try crc32(url)
        case "zip": return try zipEntryCRC(url, extensions: ["gb", "gbc", "gba"])
        default: return nil
        }
    }
    static func zipEntryCRC(_ url: URL, extensions: Set<String>) throws -> String? {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let size = try file.seekToEnd()
        // The end-of-central-directory record is 22 bytes plus a comment of up to 65,535.
        let tailLength = min(size, 65_557)
        try file.seek(toOffset: size - tailLength)
        guard let tail = try file.read(upToCount: Int(tailLength)), tail.count >= 22 else { return nil }
        let bytes = [UInt8](tail)
        func u16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func u32(_ b: [UInt8], _ i: Int) -> Int { u16(b, i) | u16(b, i + 2) << 16 }
        guard let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: { u32(bytes, $0) == 0x06054b50 }) else { return nil }
        let directorySize = u32(bytes, end + 12), directoryOffset = u32(bytes, end + 16)
        // ZIP64 archives mark these fields 0xFFFFFFFF; no Game Boy family ROM needs one.
        guard directoryOffset != 0xFFFF_FFFF, directorySize < 4_000_000, UInt64(directoryOffset + directorySize) <= size else { return nil }
        try file.seek(toOffset: UInt64(directoryOffset))
        guard let data = try file.read(upToCount: directorySize), data.count == directorySize else { return nil }
        let directory = [UInt8](data)
        var crcs: [String] = [], offset = 0
        while offset + 46 <= directory.count, u32(directory, offset) == 0x02014b50 {
            let nameLength = u16(directory, offset + 28), next = offset + 46 + nameLength + u16(directory, offset + 30) + u16(directory, offset + 32)
            guard offset + 46 + nameLength <= directory.count else { return nil }
            let name = String(decoding: directory[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            let leaf = (name as NSString).lastPathComponent
            if !name.hasPrefix("__MACOSX/"), !leaf.hasPrefix("."), extensions.contains((leaf as NSString).pathExtension.lowercased()) {
                crcs.append(String(format: "%08X", u32(directory, offset + 16)))
            }
            offset = next
        }
        // Several ROMs in one archive are ambiguous, so none is chosen.
        return crcs.count == 1 ? crcs[0] : nil
    }
    /// Finds every game under `root`. Reads nothing but DS headers and `.m3u` playlists, and writes nothing.
    public static func scan(_ root: URL) throws -> [Game] {
        let fm = FileManager.default
        var directory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { throw ArtError.message("ROM folder is unavailable. Connect your card or choose another folder.") }
        var scanError: Error?
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { _, error in scanError = error; return false }) else { throw ArtError.message("Cannot read the ROM folder.") }
        var games: [Game] = []
        var discs = Set<String>()
        var descriptorFolders: [String: Bool] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            if values.isDirectory == true {
                // Artwork, saves and MAME overlay folders hold files that look like games but are not.
                if GameSystem.supportFolders.contains(url.lastPathComponent.lowercased()) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true, let system = GameSystem.infer(url) else { continue }
            let ext = url.pathExtension.lowercased()
            let folder = url.deletingLastPathComponent()
            if ext == "bin" || ext == "img" {
                // Tracks of a disc described by a CUE, GDI or CCD sheet are not games of their own.
                if descriptorFolders[folder.path] == nil {
                    let siblings = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                    descriptorFolders[folder.path] = siblings.contains { ["cue", "gdi", "ccd"].contains($0.pathExtension.lowercased()) }
                }
                if descriptorFolders[folder.path] == true { continue }
            }
            if ext == "m3u", let text = try? String(contentsOf: url, encoding: .utf8) {
                // A multi-disc game is listed once, by its playlist.
                for line in text.split(whereSeparator: \.isNewline) {
                    let entry = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "/")
                    guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }
                    discs.insert(URL(fileURLWithPath: entry, relativeTo: folder).standardizedFileURL.path.lowercased())
                }
            }
            let code = ["nds", "dsi"].contains(ext) ? try gameCode(url) : nil
            games.append(Game(url: url, code: code, system: system))
        }
        if let scanError { throw scanError }
        return games.filter { !discs.contains($0.url.standardizedFileURL.path.lowercased()) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    /// Moves saved artwork to the Trash so a wrong match can be replaced.
    public static func removeArtwork(at url: URL) throws {
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        catch { throw ArtError.message("Could not move the artwork to the Trash: \(error.localizedDescription)") }
    }
    public static func existing(for rom: URL, settings: ExportSettings) throws -> URL? {
        let target = try settings.output(for: rom)
        let alternatives = settings.profile == .anbernic && settings.kind == .box ? [target, target.deletingPathExtension().appendingPathExtension("jpg"), target.deletingPathExtension().appendingPathExtension("jpeg")] : [target]
        return alternatives.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    public static func render(_ data: Data, settings: ExportSettings) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width <= 10000, image.height <= 10000 else { throw ArtError.message("The source is not a supported image.") }
        let widthLimit = settings.profile == .twilight ? 128 : max(32, min(settings.maxSize, 2048))
        let heightLimit = settings.profile == .twilight ? 115 : widthLimit
        let scale = min(1, min(Double(widthLimit) / Double(image.width), Double(heightLimit) / Double(image.height)))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ArtError.message("Cannot resize image.") }
        // Box art gets a white ground; labels and carts keep their transparent corners.
        if settings.kind == .box { context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
        context.interpolationQuality = .high; context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let result = NSMutableData()
        let format = settings.writesJPEG ? UTType.jpeg : UTType.png
        guard let rendered = context.makeImage(), let encoder = CGImageDestinationCreateWithData(result, format.identifier as CFString, 1, nil) else { throw ArtError.message("Cannot encode artwork.") }
        CGImageDestinationAddImage(encoder, rendered, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(encoder) else { throw ArtError.message("Image encoding failed.") }
        return result as Data
    }
    public static func save(_ data: Data, rom: URL, settings: ExportSettings) throws -> URL {
        guard FileManager.default.fileExists(atPath: rom.path) else { throw ArtError.message("ROM unavailable. Reconnect the SD card and scan again.") }
        if try existing(for: rom, settings: settings) != nil { throw ArtError.message("Artwork already exists; preserved the existing file.") }
        let output = try settings.output(for: rom)
        let rendered = try render(data, settings: settings)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".boxart-" + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try rendered.write(to: temporary, options: .withoutOverwriting)
        // FileManager refuses to move onto an existing destination.
        try FileManager.default.moveItem(at: temporary, to: output)
        return output
    }
}

