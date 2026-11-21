import XCTest
import AppKit
@testable import BoxArt
import BoxArtCore

final class SelectionTests: XCTestCase {
    @MainActor func model() -> LibraryModel {
        let model = LibraryModel()
        model.games = (0..<6).map { Game(url: URL(fileURLWithPath: "/tmp/Game \($0).nds"), code: nil) }
        return model
    }
    @MainActor func testShiftRangeAndCommandToggle() {
        let m = model(); let ids = m.games.map(\.id)
        m.select(ids[1]); m.select(ids[4], shift: true)
        XCTAssertEqual(m.selectedIDs, Set(ids[1...4]))
        m.select(ids[2], shift: true)
        XCTAssertEqual(m.selectedIDs, Set(ids[1...2]))
        m.select(ids[5], command: true); m.select(ids[1], command: true)
        XCTAssertEqual(m.selectedIDs, [ids[2], ids[5]])
        m.select(ids[3]); m.select(ids[0], shift: true)
        XCTAssertEqual(m.selectedIDs, Set(ids[0...3]))
    }
    @MainActor func testHiddenSelectionsPruned() {
        let m = model(); let ids = m.games.map(\.id)
        m.select(ids[0]); m.select(ids[5], shift: true)
        m.query = "Game 2"; m.pruneSelection()
        XCTAssertEqual(m.selectedIDs, [ids[2]])
        m.query = "Game 4"; m.pruneSelection()
        XCTAssertTrue(m.selectedIDs.isEmpty)
        m.select(ids[4], shift: true)
        XCTAssertEqual(m.selectedIDs, [ids[4]])
    }
    @MainActor func testSelectedExportUsesSnapshotAndExcludesOtherReadyCovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let m = LibraryModel()
        for i in 0..<3 {
            let url = root.appendingPathComponent("Game \(i).nds"); try Data(repeating: 0, count: 512).write(to: url)
            var game = Game(url: url, code: nil); game.artwork = bitmap.representation(using: .png, properties: [:]); game.status = .ready; m.games.append(game)
        }
        m.select(m.games[0].id); m.select(m.games[1].id, shift: true); m.getForSelected()
        m.select(m.games[2].id)
        let deadline = Date().addingTimeInterval(5)
        while m.busy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(m.busy); XCTAssertEqual(m.saved, 2)
        XCTAssertEqual(m.games[2].status, .ready)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Imgs/Game 2.png").path))
    }
}
