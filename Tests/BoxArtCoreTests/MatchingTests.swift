import XCTest
@testable import BoxArtCore

final class MatchingTests: XCTestCase {
    let index = ArtworkIndex(names: [
        "Mega Man 2 (USA)", "Mega Man 3 (USA)", "Mega Man 3 (Europe)", "Mega Man 3 (Japan)",
        "Donkey Kong (Japan, USA) (En) (SGB Enhanced)", "Donkey Kong (World) (Rev 1) (SGB Enhanced)",
        "Noobow (Japan)", "Gates of Zendocon (USA, Europe)", "Lock n' Chase (World)",
        "Sonic Colors (Japan) (En,Ja,Fr,De,Es,It)", "Sonic Colors (USA) (En,Ja,Fr,De,Es,It)",
        "Orcs _ Elves (USA) (En,Fr,De,Es,It)", "Daytona USA (USA)", "Daytona (Japan)",
        "Blue Lightning (USA, Europe) (Demo)", "Raiden (USA)", "Raiden (USA) (Beta)",
        "Parasite Eve (USA) (Disc 1)", "Parasite Eve (USA) (Disc 2)",
        "Mother 3 (Japan)", "Mother 3 (Japan) [T-En by Chewy, Jeffman and Tomato]",
        "Tony Hawk's Pro Skater 2 (USA)", "Pokemon Picross (Japan) (Proto)",
    ])
    func pick(_ name: String) -> String? { ArtworkMatcher.match(name, in: index)?.name }

    func testExactNameWinsAndIsMarkedExact() {
        XCTAssertEqual(ArtworkMatcher.match("Mega Man 3 (Europe)", in: index), .init(name: "Mega Man 3 (Europe)", exact: true))
        XCTAssertEqual(ArtworkMatcher.match("Orcs & Elves (USA) (En,Fr,De,Es,It)", in: index), .init(name: "Orcs _ Elves (USA) (En,Fr,De,Es,It)", exact: true))
    }
    func testSameTitlePrefersTheROMsRegionThenUSA() {
        XCTAssertEqual(pick("Mega Man 3 (E) [!]"), "Mega Man 3 (Europe)")
        XCTAssertEqual(pick("Mega Man 3 (J)"), "Mega Man 3 (Japan)")
        XCTAssertEqual(pick("Mega Man 3"), "Mega Man 3 (USA)")
        XCTAssertEqual(pick("Sonic Colors (J)(M6)(BAHAMUT)"), "Sonic Colors (Japan) (En,Ja,Fr,De,Es,It)")
        XCTAssertEqual(pick("Donkey Kong (Japan, USA) (SGB Enhanced)"), "Donkey Kong (Japan, USA) (En) (SGB Enhanced)")
    }
    func testNeverCrossesToADifferentTitle() {
        XCTAssertNil(pick("Mega Man 4 (USA)"))
        XCTAssertNil(pick("Mega Man (USA)"))
        XCTAssertNil(pick("Mega Man 2 - The Power Fighters (USA)"))
        XCTAssertEqual(pick("Daytona USA"), "Daytona USA (USA)")
        XCTAssertNil(pick("Daytona USA 2"))
        XCTAssertEqual(pick("Daytona_JPN_NDS-BAHAMUT"), "Daytona (Japan)")
    }
    func testTranslationsArticlesAlternateTitlesAndSceneNames() {
        XCTAssertEqual(pick("Noobow (Japan) [T-En by Stardust Crusaders v1.00]"), "Noobow (Japan)")
        XCTAssertEqual(pick("Gates of Zendocon, The (USA, Europe)"), "Gates of Zendocon (USA, Europe)")
        XCTAssertEqual(pick("Lock n' Chase ~ Lock 'n' Chase (World)"), "Lock n' Chase (World)")
        XCTAssertEqual(pick("tonyhawksproskater2"), "Tony Hawk's Pro Skater 2 (USA)")
        XCTAssertEqual(pick("Mother 3 v1.2"), "Mother 3 (Japan)")
        XCTAssertEqual(pick("Mother 3 (English v1.3)[HQ Sound]"), "Mother 3 (Japan)")
    }
    func testPrototypesAndDemosOnlyMatchTheirOwnKind() {
        XCTAssertEqual(pick("Raiden (USA) (v3.0)"), "Raiden (USA)")
        XCTAssertEqual(pick("Blue Lightning (USA) (Demo)"), "Blue Lightning (USA, Europe) (Demo)")
        XCTAssertNil(pick("Blue Lightning (USA)"))
        XCTAssertNil(pick("Pokemon Picross English"))
    }
    func testMultiDiscPlaylistTakesTheFirstDisc() {
        XCTAssertEqual(pick("Parasite Eve (USA)"), "Parasite Eve (USA) (Disc 1)")
    }
    func testDoubleExtensionIsNotPartOfTheTitle() {
        XCTAssertEqual(ArtworkMatcher.stripROMExtension("Tetris DX (World).gbc"), "Tetris DX (World)")
        XCTAssertEqual(ArtworkMatcher.stripROMExtension("Dr. Mario (World)"), "Dr. Mario (World)")
        XCTAssertEqual(Game(url: URL(fileURLWithPath: "/Roms/GBC/Tetris DX (World).gbc.zip"), code: nil).title, "Tetris DX")
    }
    func testArcadeTitlesFromDAT() {
        let dat = """
        clrmamepro (
        \tname "FBNeo - Arcade Games"
        )
        game (
        \tname "Metal Slug - Super Vehicle-001"
        \treleaseyear "1996"
        \trom ( name mslug.zip size 1 crc 0 )
        )
        game (
        \tname "'88 Games"
        \trom ( name 88games.zip size 1 crc 0 )
        )
        """
        XCTAssertEqual(ArcadeTitles.parse(dat), ["mslug": "Metal Slug - Super Vehicle-001", "88games": "'88 Games"])
    }
}

final class DetectionTests: XCTestCase {
    func system(_ path: String) -> GameSystem? { GameSystem.infer(URL(fileURLWithPath: path)) }

    func testFoldersFromHandheldFirmwares() {
        XCTAssertEqual(system("/Roms/32X/Game.zip"), .sega32x)
        XCTAssertEqual(system("/Roms/SEGACD/Game.chd"), .segacd)
        XCTAssertEqual(system("/Roms/GW/gnw_dkong.7z"), .gameAndWatch)
        XCTAssertEqual(system("/Roms/SG1000/Game.sg"), .sg1000)
        XCTAssertEqual(system("/Roms/PCECD/Game.cue"), .pcecd)
        XCTAssertEqual(system("/Roms/ARCADE/mslug.zip"), .fbneo)
        XCTAssertEqual(system("/Roms/CPS2/sfa3.zip"), .fbneo)
        XCTAssertEqual(system("/Roms/NEOGEO/mslug.zip"), .neogeo)
        XCTAssertEqual(system("/Roms/VB/Game.vb"), .virtualBoy)
        XCTAssertEqual(system("/Roms/LYNX/Game.rom"), .lynx)
        XCTAssertEqual(system("/Roms/gba/sub/Game.zip"), .gba)
    }
    func testExtensionAndFolderDisagreements() {
        // A Game Boy game kept with the Color games stays in that console's list.
        XCTAssertEqual(system("/Roms/GBC/Tetris.gb"), .gbc)
        XCTAssertEqual(system("/Roms/WS/Game.wsc"), .ws)
        XCTAssertEqual(system("/Roms/NDS/Game.gba"), .gba)
        XCTAssertEqual(system("/Roms/MD/Game.md"), .genesis)
    }
    func testFilesThatAreNotGames() {
        XCTAssertNil(system("/Roms/PORTS/thing/README.md"))
        XCTAssertNil(system("/Roms/GBA/_README.txt"))
        XCTAssertNil(system("/Roms/NDS/Game.sav"))
        XCTAssertNil(system("/Roms/Unknown/Game.zip"))
        XCTAssertNil(system("/Roms/PORTS/opentyrian/data/setup.int"))
    }
    func testEveryFolderNameBelongsToOneSystem() {
        var seen: [String: GameSystem] = [:]
        for system in GameSystem.allCases {
            for folder in system.folders {
                XCTAssertNil(seen[folder], "\(folder) is claimed by \(seen[folder]!) and \(system)")
                seen[folder] = system
            }
        }
    }
    func testScanSkipsSupportFoldersAndPlaylistDiscs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "GW/gnw_dkong.zip", "GW/artwork/gnw_dkong.zip", "GB/Imgs/Tetris.png", "GB/Tetris (World).zip", "GB/_chromatic/Deadeus.gb",
            "PS/Parasite Eve (USA).m3u", "PS/_hidden/Parasite Eve (USA) (Disc 1).chd", "PS/_hidden/Parasite Eve (USA) (Disc 2).chd", "PS/Tekken (USA).chd",
            "PORTS/game/data.zip", "PORTS/game/README.md", "SEGACD/Sonic CD (USA).cue", "SEGACD/Sonic CD (USA).bin", "A2600/Pitfall.bin",
        ]
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let body = file.hasSuffix(".m3u") ? "# discs\n_hidden/Parasite Eve (USA) (Disc 1).chd\n_hidden/Parasite Eve (USA) (Disc 2).chd\n" : "x"
            try Data(body.utf8).write(to: url)
        }
        let games = try Library.scan(root)
        let found = Set(games.map { $0.url.path.replacingOccurrences(of: root.path + "/", with: "").replacingOccurrences(of: "/private", with: "") })
        XCTAssertEqual(found, ["GW/gnw_dkong.zip", "GB/Tetris (World).zip", "GB/_chromatic/Deadeus.gb", "PS/Parasite Eve (USA).m3u", "PS/Tekken (USA).chd", "SEGACD/Sonic CD (USA).cue", "A2600/Pitfall.bin"])
        XCTAssertEqual(games.first { $0.url.lastPathComponent == "gnw_dkong.zip" }?.system, .gameAndWatch)
    }
}
