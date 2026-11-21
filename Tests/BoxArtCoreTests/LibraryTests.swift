import XCTest
import AppKit
import ImageIO
@testable import BoxArtCore

final class LibraryTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func rom(_ name: String = "Mario (USA).nds", code: String = "ASME") throws -> URL {
        let url = root.appendingPathComponent(name)
        var data = Data(repeating: 0, count: 512); data.replaceSubrange(12..<16, with: code.utf8)
        try data.write(to: url); return url
    }
    func image() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 460, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return bitmap.representation(using: .png, properties: [:])!
    }
    func cornerAlpha(_ data: Data) throws -> UInt8 {
        let image = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Drawing at full size with a one-pixel context keeps only the bottom-left corner.
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixel[3]
    }
    func testScanReadsHeadersAndIgnoresAppleDouble() throws {
        let file = try rom(); _ = try rom("._Mario.nds"); _ = try rom("Notes.txt")
        let games = try Library.scan(root)
        XCTAssertEqual(games.count, 1); XCTAssertEqual(games.first?.code, "ASME"); XCTAssertEqual(games.first?.url.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
    }
    func testLiveProvider() async throws {
        guard ProcessInfo.processInfo.environment["BOXART_LIVE_TEST"] == "1" else { throw XCTSkip("Opt-in network test") }
        let file = try rom(code: "B6ZE")
        let result = try await ArtworkService().artwork(for: Game(url: file, code: "B6ZE"))
        XCTAssertNotNil(result)
        if let result { _ = try Library.save(result.0, rom: file, settings: ExportSettings()) }
    }
    func testCartLabelsUseTheirOwnFolderAndKeepTransparency() throws {
        let file = try rom(); var settings = ExportSettings(); settings.kind = .label
        XCTAssertEqual(try settings.output(for: file).path, root.appendingPathComponent("Labels/Mario (USA).png").path)
        settings.kind = .cart
        XCTAssertEqual(try settings.output(for: file).path, root.appendingPathComponent("Carts/Mario (USA).png").path)
        // The fixture image is fully transparent; a label must stay that way, box art gets a white ground.
        XCTAssertEqual(try cornerAlpha(Library.render(image(), settings: settings)), 0)
        XCTAssertEqual(try cornerAlpha(Library.render(image(), settings: ExportSettings())), 255)
        // A saved label does not count as existing box art, and the other way round.
        _ = try Library.save(image(), rom: file, settings: settings)
        XCTAssertNotNil(try Library.existing(for: file, settings: settings))
        XCTAssertNil(try Library.existing(for: file, settings: ExportSettings()))
        // Profiles with no place for cart artwork say so instead of writing box-art paths.
        settings.profile = .retroarch; settings.destination = root
        XCTAssertThrowsError(try settings.output(for: file))
        settings.profile = .twilight
        XCTAssertThrowsError(try settings.output(for: file))
        settings.profile = .custom; settings.jpeg = true
        XCTAssertEqual(try settings.output(for: file).pathExtension, "png")
    }
    func testLiveCartLabelProvider() async throws {
        guard ProcessInfo.processInfo.environment["BOXART_LIVE_TEST"] == "1" else { throw XCTSkip("Opt-in network test") }
        let file = try rom(code: "AMCE")
        for (kind, size) in [(ArtKind.label, [272, 296]), (.cart, [336, 360])] {
            var settings = ExportSettings(); settings.kind = kind
            let result = try await ArtworkService().artwork(for: Game(url: file, code: "AMCE"), kind: kind)
            let saved = try Library.save(try XCTUnwrap(result).0, rom: file, settings: settings)
            let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: saved)))
            XCTAssertEqual([image.pixelsWide, image.pixelsHigh], size)
            XCTAssertEqual(try cornerAlpha(Data(contentsOf: saved)), 0)
        }
    }
    func testGameBoyChecksumCoversWholeFile() throws {
        let file = root.appendingPathComponent("Tetris (World).gb"); try Data("123456789".utf8).write(to: file)
        XCTAssertEqual(try Library.crc32(file), "CBF43926")
        var settings = ExportSettings(); settings.kind = .label
        XCTAssertEqual(try settings.output(for: file).path, root.appendingPathComponent("Labels/Tetris (World).png").path)
    }
    func zip(_ name: String, _ entries: [String], comment: String? = nil) throws -> URL {
        let archive = root.appendingPathComponent(name)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); process.currentDirectoryURL = root
        process.arguments = ["-q", archive.path] + entries; process.standardInput = Pipe()
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        if let comment {
            // zip -z reads the archive comment from standard input.
            let edit = Process(); edit.executableURL = process.executableURL; edit.arguments = ["-q", "-z", archive.path]
            let pipe = Pipe(); edit.standardInput = pipe; try edit.run()
            pipe.fileHandleForWriting.write(Data(comment.utf8)); try pipe.fileHandleForWriting.close(); edit.waitUntilExit()
        }
        return archive
    }
    func testZippedGameBoyChecksumComesFromCentralDirectory() throws {
        let rom = root.appendingPathComponent("Tetris (World).gb"); try Data(repeating: 7, count: 32_768).write(to: rom)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("__MACOSX"), withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("__MACOSX/._Tetris (World).gb"))
        try Data("notes".utf8).write(to: root.appendingPathComponent("readme.txt"))
        let expected = try Library.crc32(rom)
        // Deflated, alongside a readme and macOS resource-fork debris, with an archive comment.
        XCTAssertEqual(try Library.gameBoyChecksum(zip("Tetris (World).zip", ["Tetris (World).gb", "readme.txt", "__MACOSX/._Tetris (World).gb"], comment: "dumped 2026")), expected)
        let other = root.appendingPathComponent("Other.gbc"); try Data([1, 2, 3]).write(to: other)
        XCTAssertNil(try Library.gameBoyChecksum(zip("Both.zip", ["Tetris (World).gb", "Other.gbc"])))
        XCTAssertNil(try Library.gameBoyChecksum(zip("Readme.zip", ["readme.txt"])))
        let advance = root.appendingPathComponent("Mario Kart (USA).gba"); try Data(repeating: 9, count: 65_536).write(to: advance)
        XCTAssertEqual(try Library.gameBoyChecksum(zip("Mario Kart (USA).zip", ["Mario Kart (USA).gba"])), try Library.crc32(advance))
        let junk = root.appendingPathComponent("Broken.zip"); try Data(repeating: 0, count: 100).write(to: junk)
        XCTAssertNil(try Library.gameBoyChecksum(junk))
    }
    func testLiveGameBoyLabelProvider() async throws {
        guard ProcessInfo.processInfo.environment["BOXART_LIVE_TEST"] == "1" else { throw XCTSkip("Opt-in network test") }
        // The Final Fantasy Legend (USA), then a GBA game.
        // A GBA ROM goes through the same checksum lookup as a Game Boy one.
        for crc in ["0006612D", "000206C0"] {
            let result = try await ArtworkService().slotLabel(crc: crc)
            let image = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(result).0))
            XCTAssertGreaterThan(image.pixelsWide, 0)
        }
        let missing = try await ArtworkService().slotLabel(crc: "00000000")
        XCTAssertNil(missing)
    }
    func testInvalidHeaderFallsBack() throws {
        let file = root.appendingPathComponent("Homebrew.nds"); try Data([0, 1]).write(to: file)
        XCTAssertNil(try Library.gameCode(file))
    }
    func testProfileNamingPreservesExactStem() throws {
        let file = try rom(" Mario.nds")
        var settings = ExportSettings()
        XCTAssertEqual(try settings.output(for: file).lastPathComponent, " Mario.png")
        XCTAssertEqual(try settings.output(for: file).deletingLastPathComponent().lastPathComponent, "Imgs")
        settings.profile = .twilight
        XCTAssertThrowsError(try settings.output(for: file))
        settings.destination = root
        XCTAssertEqual(try settings.output(for: file).lastPathComponent, " Mario.nds.png")
    }
    func testResizeAndNeverOverwrite() throws {
        let file = try rom(); let original = try Data(contentsOf: file)
        let settings = ExportSettings()
        let output = try Library.save(image(), rom: file, settings: settings)
        let data = try Data(contentsOf: output)
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        XCTAssertEqual(decoded.width, 512); XCTAssertEqual(decoded.height, 460)
        XCTAssertThrowsError(try Library.save(image(), rom: file, settings: settings))
        XCTAssertEqual(try Data(contentsOf: output), data)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testJPEGExistingAndTwilightDimensions() throws {
        let file = try rom(); var settings = ExportSettings()
        let target = try settings.output(for: file).deletingPathExtension().appendingPathExtension("jpg")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try image().write(to: target)
        XCTAssertEqual(try Library.existing(for: file, settings: settings), target)
        XCTAssertThrowsError(try Library.save(image(), rom: file, settings: settings))
        settings.profile = .twilight; settings.destination = root
        let data = try Library.render(image(), settings: settings)
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        XCTAssertLessThanOrEqual(decoded.width, 128); XCTAssertLessThanOrEqual(decoded.height, 115)
    }
    func testInvalidImageAndMissingCard() throws {
        let file = try rom()
        XCTAssertThrowsError(try Library.save(Data("bad".utf8), rom: file, settings: ExportSettings()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Imgs").path))
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try Library.save(image(), rom: file, settings: ExportSettings()))
    }
}
