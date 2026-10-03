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
