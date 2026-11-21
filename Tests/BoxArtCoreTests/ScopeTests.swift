import XCTest
import AppKit
@testable import BoxArt
import BoxArtCore

final class ScopeTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// A library of games that already hold a preview, so no network is needed to save them.
    @MainActor func model(_ files: [String]) throws -> LibraryModel {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let m = LibraryModel(); m.profile = .anbernic; m.kind = .box; m.normalizeFilenames = false
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0, count: 64).write(to: url)
            var game = Game(url: url, code: nil); game.artwork = bitmap.representation(using: .png, properties: [:]); game.status = .ready
            m.games.append(game)
        }
        return m
    }
    @MainActor func finish(_ m: LibraryModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while m.busy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(m.busy)
    }
    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) }

    @MainActor func testOneConsoleAndSeveralConsoles() async throws {
        let m = try model(["GB/A.gb", "GB/B.gb", "GBA/C.gba", "MD/D.gen"])
        XCTAssertEqual(m.title(for: m.defaultScope), "Get artwork for all games")
        m.choose(.gb)
        XCTAssertEqual(m.title(for: m.defaultScope), "Get artwork for Game Boy")
        m.run(m.defaultScope); try await finish(m)
        XCTAssertTrue(exists("GB/Imgs/A.png")); XCTAssertTrue(exists("GB/Imgs/B.png"))
        XCTAssertFalse(exists("GBA/Imgs/C.png")); XCTAssertFalse(exists("MD/Imgs/D.png"))

        m.choose(.gba); m.choose(.genesis, adding: true)
        XCTAssertEqual(m.systems, [.gba, .genesis])
        XCTAssertEqual(m.title(for: m.defaultScope), "Get artwork for 2 consoles")
        m.choose(.genesis, adding: true)
        XCTAssertEqual(m.systems, [.gba])
        m.getArtwork(for: .genesis); try await finish(m)
        XCTAssertTrue(exists("MD/Imgs/D.png")); XCTAssertFalse(exists("GBA/Imgs/C.png"))
        XCTAssertEqual(m.systemCounts.map { "\($0.system.name) \($0.saved)/\($0.total)" }, ["Game Boy Advance 0/1", "Game Boy 2/2", "Mega Drive · Genesis 1/1"])
    }
    @MainActor func testSelectionBeatsConsoleAndSearchNarrowsShown() async throws {
        let m = try model(["GB/Alpha.gb", "GB/Beta.gb", "GB/Gamma.gb"])
        m.choose(.gb); m.query = "a"; m.filter = .unsaved
        XCTAssertEqual(m.title(for: m.defaultScope), "Get artwork for 3 shown games")
        m.query = "Alpha"; m.pruneSelection()
        XCTAssertEqual(m.title(for: m.defaultScope), "Get artwork for 1 shown game")
        m.query = ""; m.select(m.games[1].id)
        XCTAssertEqual(m.title(for: m.defaultScope), "Get artwork for 1 selected game")
        m.run(m.defaultScope); try await finish(m)
        XCTAssertEqual(m.saved, 1); XCTAssertTrue(exists("GB/Imgs/Beta.png"))
    }
    @MainActor func testCollidingNamesAreSkippedWithoutBlockingTheBatch() async throws {
        let m = try model(["GB/Same.gb", "GBC/Same.gbc", "GBA/Other.gba"])
        m.profile = .custom; m.destination = root.appendingPathComponent("out")
        m.run(.library); try await finish(m)
        XCTAssertTrue(exists("out/Other.png")); XCTAssertFalse(exists("out/Same.png"))
        XCTAssertEqual(m.games.filter { $0.status == .saveFailed }.count, 2)
        XCTAssertEqual(m.saved, 1)
        // The skipped pair keep their previews and can be exported one at a time.
        XCTAssertEqual(m.ready, 2)
        m.getArtwork(ids: [m.games[0].id]); try await finish(m)
        XCTAssertTrue(exists("out/Same.png")); XCTAssertEqual(m.games[0].status, .saved); XCTAssertEqual(m.saved, 2)
    }
    @MainActor func testSameGameInTwoFormatsSharesOneCover() async throws {
        let m = try model(["GW/gnw_dkong.zip", "GW/gnw_dkong.7z", "GW/gnw_egg.zip"])
        m.run(.library); try await finish(m)
        XCTAssertEqual(m.saved, 3)
        XCTAssertEqual(m.games.filter { $0.status == .saved }.count, 3)
        XCTAssertTrue(exists("GW/Imgs/gnw_dkong.png")); XCTAssertTrue(exists("GW/Imgs/gnw_egg.png"))
    }
    @MainActor func testSavedPreviewLeavesMemoryAndTrashRestoresMissing() async throws {
        let m = try model(["GB/A.gb"])
        m.run(.library); try await finish(m)
        XCTAssertNil(m.games[0].artwork); XCTAssertEqual(m.games[0].status, .saved)
        m.run(.library)
        XCTAssertFalse(m.busy, "nothing left to do")
        m.removeArtwork(for: [m.games[0].id])
        XCTAssertNil(m.games[0].savedURL); XCTAssertEqual(m.games[0].status, .missing); XCTAssertFalse(exists("GB/Imgs/A.png"))
    }
    /// Real names from a handheld's card, looked up and saved into a temporary library.
    @MainActor func testLiveLibraryRun() async throws {
        guard ProcessInfo.processInfo.environment["BOXART_LIVE_TEST"] == "1" else { throw XCTSkip("Opt-in network test") }
        let files = [
            "GB/Noobow (Japan) [T-En by Stardust Crusaders v1.00].zip", "GB/Donkey Kong (Japan, USA) (SGB Enhanced).zip", "GB/Deadeus.zip",
            "GBC/Tetris Blast (USA, Europe) (SGB Enhanced).gb", "GBC/Pokemon - Gold Version (USA, Europe).zip",
            "MD/Ghostbusters (USA, Europe).zip", "GG/Sylvan Tale (Japan) (Translated).zip", "LYNX/Qix (USA, Europe).lnx",
            "SFC/Donkey Kong Country (U) (V1.2) [!].smc", "PS/tonyhawksproskater2.chd", "PS/Parasite Eve (USA).m3u",
            "ARCADE/mslug.zip", "GW/gnw_dkong.zip", "GW/gnw_ball.zip", "GBA/Mother 3 v1.2.zip",
        ]
        let m = try model(files)
        for i in m.games.indices { m.games[i].artwork = nil; m.games[i].status = .missing }
        m.run(.library)
        let deadline = Date().addingTimeInterval(120)
        while m.busy && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        for game in m.games.sorted(by: { $0.id < $1.id }) { print("LIVE \(game.status.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(game.system.name) / \(game.url.lastPathComponent)  ←  \(game.source)") }
        print("LIVE \(m.message)")
        XCTAssertFalse(m.busy)
        let missed = Set(m.games.filter { $0.savedURL == nil }.map { $0.url.lastPathComponent })
        XCTAssertEqual(missed, ["Deadeus.zip", "gnw_ball.zip"])
    }
}
