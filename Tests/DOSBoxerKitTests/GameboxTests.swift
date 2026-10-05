import Foundation
import Testing
@testable import DOSBoxerKit

/// Imports, launcher detection and Boxer gamebox reading, using fixture games
/// made on the fly (no game files are committed).
@MainActor
struct GameboxTests {
    let scratch: URL

    init() throws {
        scratch = FileManager.default.temporaryDirectory
            .appending(path: "dosboxer-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    /// A fake game folder: a start script, the game, a setup tool and box art.
    private func makeGameFolder(named name: String) throws -> URL {
        let folder = scratch.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "CC1"), withIntermediateDirectories: true)
        for file in ["run.bat", "CC1/CC1.EXE", "CC1/SETUP.EXE", "readme.txt", "ai-boxart.jpeg"] {
            try Data("x".utf8).write(to: folder.appending(path: file))
        }
        return folder
    }

    @Test func theProgramNamedAfterTheGameBeatsGenericNames() throws {
        let folder = scratch.appending(path: "covertac", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in ["GAME.EXE", "COVERT.EXE", "INTRO.EXE", "TAC.EXE"] {
            try Data("x".utf8).write(to: folder.appending(path: file))
        }
        let launchers = LauncherFinder.launchers(inDrive: "C", root: folder, gameName: "Covert Action (1990)")
        #expect(launchers.first(where: \.isDefault)?.dosPath == "C:\\COVERT.EXE")

        let dredd = scratch.appending(path: "dredd", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dredd, withIntermediateDirectories: true)
        for file in ["3DLEV.EXE", "JD.EXE", "VIDCOM.EXE"] {
            try Data("x".utf8).write(to: dredd.appending(path: file))
        }
        let dreddLaunchers = LauncherFinder.launchers(inDrive: "C", root: dredd, gameName: "Judge Dredd (1997)")
        #expect(dreddLaunchers.first(where: \.isDefault)?.dosPath == "C:\\JD.EXE")
    }

    @Test func newerGamesGetMoreMemory() {
        #expect(Gamebox.eraSettings(year: 1995)["dosbox memsize"] == "64")
        #expect(Gamebox.eraSettings(year: 1990).isEmpty)
        #expect(Gamebox.fixingSettings(#"CONFIG -set "mididevice=default""#) == #"CONFIG -set "mididevice=port""#)
    }

    @Test func aDiscInSeveralFormatsIsMountedOnceAsItsCueSheet() throws {
        let folder = scratch.appending(path: "cd", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in ["ATLANTIS.ccd", "ATLANTIS.cue", "ATLANTIS.img", "ATLANTIS.sub", "DISC2.iso"] {
            try Data("x".utf8).write(to: folder.appending(path: file))
        }
        #expect(DiscImageFinder.discs(in: folder).map(\.lastPathComponent) == ["ATLANTIS.cue", "DISC2.iso"])
    }

    @Test func importingAFolderMakesAGamebox() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = try makeGameFolder(named: "Crystal Caves (1991)")

        let url = try GameImporter.makeGamebox(from: source, inLibrary: library)
        let gamebox = try Gamebox.open(url)

        #expect(url.lastPathComponent == "Crystal Caves (1991).dosgame")
        #expect(gamebox.name == "Crystal Caves (1991)")
        #expect(gamebox.info.drives == [Gamebox.Drive(letter: "C", kind: .hardDisk, path: "Drives/C")])
        #expect(gamebox.coverURL?.lastPathComponent == "Cover.jpeg")
        // The start script wins; setup tools never become the default
        #expect(gamebox.defaultLauncher?.dosPath == "C:\\run.bat")
        #expect(gamebox.info.launchers.contains { $0.dosPath == "C:\\CC1\\CC1.EXE" })
        #expect(gamebox.info.launchers.last?.title == "Setup")
        // The original folder is untouched
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "run.bat").path(percentEncoded: false)))
    }

    @Test func importingAZipUsesItsTopFolder() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = try makeGameFolder(named: "CrystalC")
        let zip = scratch.appending(path: "Crystal Caves (1991).zip")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", source.path(percentEncoded: false), zip.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()

        let gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: zip, inLibrary: library))

        #expect(gamebox.name == "Crystal Caves (1991)")
        #expect(gamebox.defaultLauncher?.dosPath == "C:\\run.bat")
    }

    /// eXoDOS archives: an empty .exo placeholder beside a folder that holds
    /// the game a few levels down.
    @Test func importingAnExoDOSStyleZip() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let staging = scratch.appending(path: "staging", directoryHint: .isDirectory)
        let game = staging.appending(path: "WOLF3D/WOLF3D", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging.appending(path: "WOLF3D/HELP"), withIntermediateDirectories: true)
        try Data().write(to: staging.appending(path: "Wolfenstein 3D (1992).exo"))
        try Data("x".utf8).write(to: game.appending(path: "WOLF3D.EXE"))
        try Data("x".utf8).write(to: staging.appending(path: "WOLF3D/HELP/HELP.EXE"))
        let zip = scratch.appending(path: "Wolfenstein 3D (1992).zip")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", staging.path(percentEncoded: false), zip.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()

        let gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: zip, inLibrary: library))

        #expect(gamebox.defaultLauncher?.dosPath == "C:\\WOLF3D\\WOLF3D.EXE")
        // The archive's top folder is eXoDOS's short name (finds controller mappings)
        #expect(gamebox.info.shortName == "WOLF3D")
    }

    /// eXoDOS Duke Nukem: its start script sits at the top, beside a folder
    /// of per-episode scripts.
    @Test func prefersTheTopLevelStartScript() throws {
        let folder = scratch.appending(path: "Duke", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "DUKE1"), withIntermediateDirectories: true)
        for file in ["DN1.BAT", "DUKE1/DUKE1.BAT", "DUKE1/DUKE2.BAT", "DUKE1/DUKE3.BAT"] {
            try Data("x".utf8).write(to: folder.appending(path: file))
        }
        let launchers = LauncherFinder.launchers(inDrive: "C", root: folder,
                                                 gameName: "Duke Nukem - Episode 1 - Shrapnel City (1991)")
        #expect(launchers.first?.dosPath == "C:\\DN1.BAT")
        #expect(launchers.dropFirst().first?.dosPath == "C:\\DUKE1\\DUKE1.BAT")
    }

    /// eXoDOS CD games: the disc image sits in a cd folder beside the game.
    @Test func mountsDiscImagesAsDriveD() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let folder = scratch.appending(path: "fullt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "cd"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appending(path: "THROTTLE"), withIntermediateDirectories: true)
        for file in ["cd/fullt.cue", "cd/fullt.BIN", "THROTTLE/THROTTLE.EXE"] {
            try Data("x".utf8).write(to: folder.appending(path: file))
        }

        let gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: folder, inLibrary: library))

        #expect(gamebox.info.drives.last == Gamebox.Drive(letter: "D", kind: .cdROM, path: "Drives/C/cd/fullt.cue"))
        let commands = try gamebox.sessionArguments().joined(separator: "\n")
        #expect(commands.contains("@MOUNT D \"\(gamebox.url.appending(path: "Drives/C/cd/fullt.cue").path(percentEncoded: false))\" -t cdrom >NUL"))
    }

    @Test func menuScriptsBecomeNamedPrograms() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let folder = scratch.appending(path: "Boxing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "VBOX.EXE"))
        try Data("""
            echo Press 1 for Boxing w/ SoundBlaster\r
            echo Press 2 for Boxing w/ MT-32\r
            echo Press 3 to Quit\r
            choice /C:123 /N\r
            if errorlevel = 2 goto MT32\r
            if errorlevel = 1 goto SB16\r
            :SB16\r
            @vbox\r
            goto quit\r
            :MT32\r
            CONFIG -set "mididevice=mt32"\r
            @vbox\r
            goto quit
            """.utf8).write(to: folder.appending(path: "run.bat"))

        let gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: folder, inLibrary: library))

        #expect(gamebox.info.launchers.prefix(2).map(\.title) == ["Boxing w/ SoundBlaster", "Boxing w/ MT-32"])
        #expect(gamebox.defaultLauncher?.title == "Boxing w/ SoundBlaster")
        #expect(gamebox.info.launchers.contains { $0.title == "Menu" })
        let mt32 = try gamebox.sessionArguments(.launcher(gamebox.info.launchers[1]))
        #expect(mt32.contains("@CONFIG -set \"mididevice=mt32\""))
        #expect(mt32.contains("@vbox"))
        #expect(mt32.last == "@EXIT")
    }

    @Test func sameNameGetsANumber() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = try makeGameFolder(named: "Keen")
        _ = try GameImporter.makeGamebox(from: source, inLibrary: library)
        let second = try GameImporter.makeGamebox(from: source, inLibrary: library)
        #expect(second.lastPathComponent == "Keen 2.dosgame")
    }

    @Test func sessionMountsSavesAsAnOverlayAndRunsTheGame() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: try makeGameFolder(named: "Game"),
                                                                    inLibrary: library))
        let commands = try gamebox.sessionArguments().joined(separator: "\n")

        #expect(commands.contains("MOUNT C \"\(gamebox.url.appending(path: "Drives/C").path(percentEncoded: false))\""))
        #expect(commands.contains("MOUNT -t overlay C \"\(gamebox.savesURL.appending(path: "C").path(percentEncoded: false))"))
        #expect(commands.contains("@C:\n-c\n@CD \\\n-c\n@CALL run.bat"))
    }

    @Test func gameSessionsExitWhenTheGameEnds() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        var gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: try makeGameFolder(named: "Game"),
                                                                    inLibrary: library))
        let game = try gamebox.sessionArguments(.game)
        #expect(game.last == "@EXIT")
        #expect(game.contains("@CALL run.bat"))           // batch files must return
        #expect(!game.joined().contains("\u{1B}[44m"))    // no header before a game
        #expect(try gamebox.sessionArguments(.prompt).joined().contains("\u{1B}[44m"))
        #expect(try gamebox.sessionArguments(.prompt).contains("@EXIT") == false)
        gamebox.info.quitsWhenGameEnds = false
        #expect(try gamebox.sessionArguments(.game).contains("@EXIT") == false)
    }

    @Test func readsOriginalBoxerGameboxes() throws {
        let boxer = scratch.appending(path: "X-COM Demo.boxer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: boxer.appending(path: "C.harddisk/XCOMDEMO"),
                                                withIntermediateDirectories: true)
        let plist: [String: Any] = ["BXDefaultProgramPath": "C.harddisk/XCOMDEMO/XCOM.BAT",
                                    "BXGameIdentifier": "644E7CBAB999DB002669A9AD0B0F91722D095C22"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: boxer.appending(path: "Game Info.plist"))

        let gamebox = try Gamebox.open(boxer)

        #expect(gamebox.name == "X-COM Demo")
        #expect(gamebox.info.drives.first == Gamebox.Drive(letter: "C", kind: .hardDisk, path: "C.harddisk"))
        #expect(gamebox.defaultLauncher?.dosPath == "C:\\XCOMDEMO\\XCOM.BAT")
        // Writes never go inside someone else's package
        #expect(!gamebox.savesURL.path(percentEncoded: false).hasPrefix(boxer.path(percentEncoded: false)))
        // The same Boxer game always gets the same ID
        #expect(try Gamebox.open(boxer).id == gamebox.id)
    }

    @Test func convertsBoxerGameboxesIntoTheLibrary() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let boxer = scratch.appending(path: "Epic Pinball.boxer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: boxer.appending(path: "C.harddisk/PINBALL"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: boxer.appending(path: "Disc 1.cdrom"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: boxer.appending(path: "C.harddisk/PINBALL/PINBALL.EXE"))
        let plist = ["BXDefaultProgramPath": "C.harddisk/PINBALL/PINBALL.EXE"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: boxer.appending(path: "Game Info.plist"))

        let gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: boxer, inLibrary: library))

        #expect(gamebox.url.pathExtension == "dosgame")
        #expect(gamebox.info.drives == [
            Gamebox.Drive(letter: "C", kind: .hardDisk, path: "Drives/C"),
            Gamebox.Drive(letter: "D", kind: .cdROM, path: "Drives/D"),
        ])
        #expect(gamebox.defaultLauncher?.dosPath == "C:\\PINBALL\\PINBALL.EXE")
        #expect(FileManager.default.fileExists(
            atPath: gamebox.url.appending(path: "Drives/C/PINBALL/PINBALL.EXE").path(percentEncoded: false)))
    }

    @Test func renamingChangesTheNameAndThePackage() throws {
        let root = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try GameImporter.makeGamebox(from: try makeGameFolder(named: "Keen1"), inLibrary: root)
        let library = GameLibrary()
        library.useLibrary(at: root)
        defer { UserDefaults.standard.removeObject(forKey: "LibraryPath") }

        library.rename(library.games[0], to: "Commander Keen: Marooned on Mars")

        #expect(library.games.map(\.name) == ["Commander Keen: Marooned on Mars"])
        // Games at the top of the library were tidied into Games
        #expect(library.games[0].url.deletingLastPathComponent().lastPathComponent == "Games")
        #expect(library.games[0].url.lastPathComponent == "Commander Keen- Marooned on Mars.dosgame")
    }

    @Test func playStatsAddUpAcrossMacs() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let url = try GameImporter.makeGamebox(from: try makeGameFolder(named: "Game (1991)"), inLibrary: library)
        let start = Date(timeIntervalSinceNow: -600)
        PlayStats.recordSession(of: try Gamebox.open(url), startedAt: start)
        // Another Mac's stats file, synced in
        let other = PlayStats(launches: 2, lastPlayed: Date(timeIntervalSinceNow: -86_400), secondsPlayed: 100)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(other).write(to: url.appending(path: "Stats/other-mac.json"))

        let gamebox = try Gamebox.open(url)

        #expect(gamebox.stats.launches == 3)
        #expect(gamebox.stats.secondsPlayed >= 699)
        #expect(gamebox.year == 1991)
        #expect(gamebox.info.dateAdded != nil)
    }

    /// Read-only gameboxes (saves kept elsewhere) must never be written to.
    @Test func gamesWithOutsideSavesAreNeverWrittenTo() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        var gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: try makeGameFolder(named: "Game"),
                                                                    inLibrary: library))
        gamebox.externalSavesURL = scratch.appending(path: "Outside Saves", directoryHint: .isDirectory)
        let before = try FileManager.default.contentsOfDirectory(atPath: gamebox.url.path(percentEncoded: false))

        _ = try gamebox.sessionArguments()
        GameboxPresence.markInUse(gamebox)
        PlayStats.recordSession(of: gamebox, startedAt: Date())

        #expect(gamebox.isReadOnly)
        #expect(try FileManager.default.contentsOfDirectory(atPath: gamebox.url.path(percentEncoded: false)) == before)
    }

    @Test func collectionsAreSavedInTheLibrary() throws {
        let root = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "Games"), withIntermediateDirectories: true)
        _ = try GameImporter.makeGamebox(from: try makeGameFolder(named: "Keen"), inLibrary: root.appending(path: "Games"))
        let library = GameLibrary()
        library.useLibrary(at: root)
        defer { UserDefaults.standard.removeObject(forKey: "LibraryPath") }

        let collection = library.createCollection(named: "Apogee")
        library.add([library.games[0].id, library.games[0].id], toCollection: collection.id)
        library.renameCollection(collection.id, to: "Apogee Classics")

        // Reading the library afresh finds the same collection, game listed once
        library.reload()
        #expect(library.collections.map(\.name) == ["Apogee Classics"])
        #expect(library.collections[0].gameIDs == [library.games[0].id])

        library.remove(library.games[0].id, fromCollection: collection.id)
        library.deleteCollection(collection.id)
        library.reload()
        #expect(library.collections.isEmpty)
    }

    @Test func renamingByTitleKeepsTheYear() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: try makeGameFolder(named: "Crystal Caves (1991)"),
                                                                    inLibrary: library))
        #expect(gamebox.title == "Crystal Caves")
        #expect(gamebox.name(forTitle: "Crystal Caves Vol. 1 ") == "Crystal Caves Vol. 1 (1991)")
        #expect(gamebox.name(forTitle: "Crystal Caves (1992)") == "Crystal Caves (1992)")
    }

    @Test func revertingDeletesOnlySaves() throws {
        let library = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let gamebox = try Gamebox.open(try GameImporter.makeGamebox(from: try makeGameFolder(named: "Game"),
                                                                    inLibrary: library))
        _ = try gamebox.sessionArguments()  // creates Saves/C
        try Data("save".utf8).write(to: gamebox.savesURL.appending(path: "C/SAVE1.DAT"))

        try gamebox.revertToOriginal()

        #expect(!FileManager.default.fileExists(atPath: gamebox.savesURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: gamebox.url.appending(path: "Drives/C/run.bat").path(percentEncoded: false)))
    }
}
