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
        #expect(Gamebox.eraSettings(year: 1997)["dosbox memsize"] == "64")
        #expect(Gamebox.eraSettings(year: 1989)["cpu cpu_cycles"] == "1500")
        #expect(Gamebox.eraSettings(year: 1991)["cpu cpu_cycles"] == "3000")
        #expect(Gamebox.eraSettings(year: 1994)["cpu cpu_cycles"] == "8000")
        #expect(Gamebox.eraSettings(year: 1995)["cpu cpu_cycles"] == "20000")
        #expect(Gamebox.eraSettings(year: 1994)["dosbox memsize"] == "32")
        #expect(Gamebox.eraSettings(year: 1996)["dosbox memsize"] == "64")
        #expect(Gamebox.eraSettings(year: 1997)["cpu cpu_cycles_protected"] == "300000")
        #expect(Gamebox.eraSettings(year: 1997)["cpu cpu_cycles"] == "60000")
        #expect(Gamebox.eraSettings(year: 1995)["cpu cpu_cycles_protected"] == nil)
        #expect(Gamebox.eraSettings(year: 1983)["cpu cpu_cycles"] == "500")
        #expect(Gamebox.eraSettings(year: 1986)["cpu cpu_cycles"] == "1500")
        #expect(Gamebox.fixingSettings(#"CONFIG -set "mididevice=default""#) == #"CONFIG -set "mididevice=coreaudio""#)
    }

    @Test func aDiscInSeveralFormatsIsMountedOnceAsItsCueSheet() throws {
        let folder = scratch.appending(path: "cd", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in ["ATLANTIS.ccd", "ATLANTIS.cue", "ATLANTIS.img", "ATLANTIS.sub", "DISC2.iso"] {
            try Data("x".utf8).write(to: folder.appending(path: file))
        }
        #expect(DiscImageFinder.discs(in: folder).map(\.lastPathComponent) == ["ATLANTIS.cue", "DISC2.iso"])
    }

    /// GW-BASIC games start their program, recognized by its saved format
    /// whatever its name (Draw Poker's is POKER.COL).
    /// Each era's normal speed is one of the Speed menu's machines, and
    /// stepping matches Faster and Slower.
    @Test func defaultSpeedsAreMachinesAndStepByTenPercent() throws {
        let games = scratch.appending(path: "Games", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        for (name, machine) in [("Snipes (1982)", "IBM XT"), ("Dig Dug (1987)", "IBM AT 286"), ("Lemmings (1991)", "Fast 286"),
                                ("Doom (1993)", "386"), ("Hexen (1995)", "486"), ("Blood (1997)", "Pentium")] {
            let game = try Gamebox.open(try GameImporter.makeGamebox(from: try makeGameFolder(named: name), inLibrary: games))
            #expect(Gamebox.Machine.matching(game.defaultSpeed)?.name == machine, "\(name)")
            #expect(!game.hasOwnSpeed)
        }
        let speed = Gamebox.Speed(realMode: "20000", protectedMode: "60000")
        #expect(speed.stepped(faster: true) == Gamebox.Speed(realMode: "22000", protectedMode: "66000"))
        #expect(speed.stepped(faster: false)?.realMode == "18182")
        #expect(Gamebox.Speed(realMode: "max", protectedMode: "max").stepped(faster: true) == nil)
    }

    @Test func shippedSettingsMatchByNameThenUnambiguousLaunchBoxEntry() throws {
        let games = scratch.appending(path: "Games", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        let url = try GameImporter.makeGamebox(from: try makeGameFolder(named: "Snipes (1982)"), inLibrary: games)
        var snipes = try Gamebox.open(url)
        let entries = [
            ShippedGameSettings.Entry(name: "Snipes (1982)", launchBoxID: nil, speed: "131", start: nil),
            ShippedGameSettings.Entry(name: "Pac Man (1982)", launchBoxID: 7, speed: "283", start: nil),
            ShippedGameSettings.Entry(name: "Pac-Man (1982)", launchBoxID: 7, speed: "1005", start: nil),
        ]
        #expect(ShippedGameSettings.entry(for: snipes, in: entries)?.speed == "131")
        snipes.info.name = "Something Else"
        snipes.info.launchBoxID = 7  // two shipped games share it: no guess
        #expect(ShippedGameSettings.entry(for: snipes, in: entries) == nil)
        // The real file ships inside the app and loads
        #expect(ShippedGameSettings.all.contains { $0.name == "Hoser (1982)" && $0.start == "C:\\AUTOEXEC.BAT" })
    }

    @Test func basicGamesStartTheirProgram() throws {
        let folder = scratch.appending(path: "DrawPoke", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: folder.appending(path: "GWBASIC.EXE"))
        for name in ["LOGO.BAS", "POKER.COL", "POKER.MON"] {
            try Data([0xFF, 0x60, 0x0F, 0x0A]).write(to: folder.appending(path: name))
        }
        try Data([0x24, 0x00]).write(to: folder.appending(path: "MAP1.MAP"))  // data, not a program

        let launchers = LauncherFinder.launchers(inDrive: "C", root: folder, gameName: "Draw Poker (1982)")
        let start = try #require(launchers.first { $0.isDefault })
        #expect(start.commands == ["GWBASIC POKER.COL"])
        #expect(launchers.filter { $0.commands != nil }.count == 3)
    }

    /// The same game added again is a duplicate even when the copy already
    /// there took its proper name.
    @MainActor @Test func duplicatesIgnorePunctuationAndThe() {
        #expect(GameLibrary.duplicateKey("Jill of the Jungle - The Complete Trilogy")
                == GameLibrary.duplicateKey("Jill of the Jungle: The Complete Trilogy"))
        #expect(GameLibrary.duplicateKey("The Dig") == GameLibrary.duplicateKey("Dig"))
        #expect(GameLibrary.duplicateKey("Doom") != GameLibrary.duplicateKey("Doom II"))
    }

    /// A Windows copy of a game (Steam, GOG) brings DOSBox along; it's left
    /// out, while a game folder that only sounds like it stays.
    @Test func leavesOutBundledDOSBox() throws {
        let game = scratch.appending(path: "Duke Nukem 3D", directoryHint: .isDirectory)
        for file in ["DUKE3D.EXE", "DOSBox/DOSBox.exe", "DOSBox/SDL.dll", "dosbox_cfg/notes.txt"] {
            let url = game.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        let games = scratch.appending(path: "Games", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        let url = try GameImporter.makeGamebox(from: game, inLibrary: games)
        let driveC = url.appending(path: "Drives/C")
        #expect(!FileManager.default.fileExists(atPath: driveC.appending(path: "DOSBox").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: driveC.appending(path: "dosbox_cfg").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: driveC.appending(path: "DUKE3D.EXE").path(percentEncoded: false)))
    }

    /// Games that boot from their own floppies: a numbered set is one
    /// launcher (disk 1 first), alternative versions are one launcher each.
    @Test func gamesThatBootFromFloppiesGetBootLaunchers() throws {
        func folder(_ name: String, _ files: [String]) throws -> URL {
            let root = scratch.appending(path: name, directoryHint: .isDirectory)
            for file in files {
                let url = root.appending(path: file)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(count: 368_640).write(to: url)
            }
            return root
        }
        let kq2 = LauncherFinder.bootLaunchers(in: try folder("kq2", ["KQ2V11H2.IMG", "KQ2V11H1.IMG"]))
        #expect(kq2.map(\.commands) == [[#"BOOT "C:\KQ2V11H1.IMG" "C:\KQ2V11H2.IMG" -l a"#]])
        let f15 = LauncherFinder.bootLaunchers(in: try folder("f15", ["floppy/cga.img", "floppy/ega.img"]))
        #expect(f15.map(\.title) == ["Boot EGA Disk", "Boot CGA Disk"])
        #expect(f15.first?.isDefault == true)
        #expect(LauncherFinder.bootLaunchers(in: try folder("none", ["README.TXT"])).isEmpty)
    }

    /// A GOG Mac installer adds the game folder inside it, named as GOG
    /// names it; a ScummVM-only one (no DOS program) is refused.
    @Test func addsGamesFromGOGInstallers() throws {
        func installer(named name: String, title: String, files: [String]) throws -> URL {
            let root = scratch.appending(path: "\(name)-root/Contents/Resources", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root.appending(path: "game"), withIntermediateDirectories: true)
            try Data(#"{"name": "\#(title)"}"#.utf8).write(to: root.appending(path: "goggame-1.info"))
            for file in files { try Data("x".utf8).write(to: root.appending(path: "game/\(file)")) }
            let package = scratch.appending(path: "\(name).pkg")
            let pkgbuild = Process()
            pkgbuild.executableURL = URL(filePath: "/usr/bin/pkgbuild")
            pkgbuild.arguments = ["--root", scratch.appending(path: "\(name)-root").path(percentEncoded: false),
                                  "--identifier", "test.\(name)", "--install-location", "/tmp/\(name)",
                                  package.path(percentEncoded: false)]
            pkgbuild.standardOutput = FileHandle.nullDevice
            try pkgbuild.run()
            pkgbuild.waitUntilExit()
            return package
        }
        let games = scratch.appending(path: "Games", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)

        let jill = try installer(named: "jill", title: "Jill of the Jungle: The Complete Trilogy", files: ["JILL1.EXE"])
        let url = try GameImporter.makeGamebox(from: jill, inLibrary: games)
        #expect(url.deletingPathExtension().lastPathComponent == "Jill of the Jungle - The Complete Trilogy")
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "Drives/C/JILL1.EXE").path(percentEncoded: false)))

        let sky = try installer(named: "sky", title: "Beneath a Steel Sky", files: ["sky.dsk"])
        #expect(throws: (any Error).self) { try GameImporter.makeGamebox(from: sky, inLibrary: games) }
    }

    /// A game whose programs are only on its CD (like The Dig) starts the
    /// one in the game's folder there, not the installer at the top.
    @Test func gamesOnlyOnCDStartFromTheCD() throws {
        let disc = scratch.appending(path: "disc", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: disc.appending(path: "DIG"), withIntermediateDirectories: true)
        for file in ["DIG.EXE", "DIG/DIG.EXE", "DIG/IMUSE.EXE", "README.TXT"] {
            try Data("x".utf8).write(to: disc.appending(path: file))
        }
        let image = scratch.appending(path: "dig.iso")
        let hdiutil = Process()
        hdiutil.executableURL = URL(filePath: "/usr/bin/hdiutil")
        hdiutil.arguments = ["makehybrid", "-iso", "-o", image.path(percentEncoded: false), disc.path(percentEncoded: false)]
        hdiutil.standardOutput = FileHandle.nullDevice
        try hdiutil.run()
        hdiutil.waitUntilExit()

        let files = try #require(CDImage.files(in: image))
        #expect(Set(files.map { $0.uppercased() }).isSuperset(of: ["DIG.EXE", "DIG/DIG.EXE", "DIG/IMUSE.EXE"]))
        let launchers = LauncherFinder.launchersOnCD(image, inDrive: "D", gameName: "The Dig (1995)")
        #expect(launchers.first(where: \.isDefault)?.dosPath.uppercased() == "D:\\DIG\\DIG.EXE")
    }

    /// Drive C moves into the game's folder only when its scripts need it.
    @Test func driveCStartsAtTheGamesFolderOnlyWhenItsScriptsSaySo() throws {
        func game(_ script: String) throws -> URL {
            let root = scratch.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let inner = root.appending(path: "DOTT/DOTT.CD", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: root.appending(path: "Game.exo"))
            try Data("menu".utf8).write(to: root.appending(path: "DOTT/run.bat"))
            try Data(script.utf8).write(to: inner.appending(path: "DOTTR.BAT"))
            try Data("x".utf8).write(to: inner.appending(path: "TENTACLE.EXE"))
            return root
        }
        #expect(LauncherFinder.menuFolder(in: try game("c:\\dott.cd\\tentacle.exe R"))?.lastPathComponent == "DOTT")
        #expect(LauncherFinder.menuFolder(in: try game("cd dott.cd\r\ntentacle R")) == nil)
    }

    @Test func aGravisChoiceTurnsOnTheGravis() throws {
        let games = scratch.appending(path: "Games", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        var game = try Gamebox.open(try GameImporter.makeGamebox(from: try makeGameFolder(named: "Crusader"), inLibrary: games))
        let gravis = Gamebox.Launcher(title: "Crusader w/ Gravis Ultrasound", dosPath: "C:\\run.bat", commands: ["CRUSADER"])
        let blaster = Gamebox.Launcher(title: "Crusader w/ SoundBlaster", dosPath: "C:\\run.bat", commands: ["CRUSADER"])
        game.info.launchers = [gravis, blaster]
        #expect(try game.sessionArguments(.launcher(gravis)).contains("gus gus=true"))
        #expect(!(try game.sessionArguments(.launcher(blaster)).contains("gus gus=true")))
    }

    /// Albion's sound effects are set up for a Gravis Ultrasound.
    /// Blackthorne: the game's own program is the default; its menu script,
    /// one folder down, adds its options without taking over.
    @Test func aMenuScriptThatIsntTheDefaultAddsItsOptions() throws {
        let folder = scratch.appending(path: "Blackthorne", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "BTHORNE/SB16"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "BTHORNE/BTHORNE.EXE"))
        let menu = #"""
        :menu
        @echo off
        cls
        echo.
        echo Press 1 for Blackthorne w/ SoundBlaster
        echo Press 2 for Blackthorne w/ Gravis Ultrasound
        echo Press 3 for Blackthorne w/ Sound Canvas
        echo Press 4 to Quit
        echo.
        choice /C:1234 /N Please Choose:
        
        if errorlevel = 4 goto quit
        if errorlevel = 3 goto SC55
        if errorlevel = 2 goto GUS
        if errorlevel = 1 goto SB16
        
        :SB16
        CONFIG -set "mididevice=default"
        copy .\sb16\*.* .\
        cls
        @BTHORNE
        goto quit
        
        :GUS
        CONFIG -set "mididevice=default"
        copy .\gus\*.* .\
        cls
        @call BTHORNEG
        goto quit
        
        :SC55
        CONFIG -set "mididevice=fluidsynth"
        copy .\sc55\*.* .\
        cls
        @BTHORNE
        goto quit
        
        :quit
        exit
        """#
        try Data(menu.utf8).write(to: folder.appending(path: "BTHORNE/run.bat"))

        let found = LauncherFinder.launchers(inDrive: "C", root: folder, gameName: "Blackthorne (1994)")
        let launchers = LauncherFinder.expandingMenus(found, root: folder)
        #expect(launchers.first(where: \.isDefault)?.dosPath == "C:\\BTHORNE\\BTHORNE.EXE")
        #expect(launchers.contains { $0.title == "Blackthorne w/ SoundBlaster" && $0.commands != nil && !$0.isDefault }, "\(launchers.map { ($0.title, $0.dosPath, $0.isDefault) })")
    }

    @Test func theBestSoundOptionIsChosenOnce() {
        func info(_ titles: [String]) -> Gamebox.Info {
            var info = Gamebox.Info(name: "Game")
            info.launchers = [Gamebox.Launcher(title: "GAME.EXE", dosPath: "C:\\GAME.EXE", isDefault: true)]
                + titles.map { Gamebox.Launcher(title: $0, dosPath: "C:\\run.bat", commands: ["GAME"]) }
            return info
        }
        let titles = ["Game w/ SoundBlaster", "Game w/ MT-32", "Game w/ Sound Canvas"]
        var early = info(titles)
        early.chooseBestSound(year: 1990, hasMT32: true)
        #expect(early.launchers.first(where: \.isDefault)?.title == "Game w/ MT-32")
        var noROMs = info(titles)
        noROMs.chooseBestSound(year: 1990, hasMT32: false)
        // No better option for its era: still one of the menu's choices
        #expect(noROMs.launchers.first(where: \.isDefault)?.title == "Game w/ SoundBlaster")
        var late = info(titles)
        late.chooseBestSound(year: 1994, hasMT32: false)
        #expect(late.launchers.first(where: \.isDefault)?.title == "Game w/ Sound Canvas")
        // Only once: a choice made afterwards is left alone
        late.launchers = late.launchers.map { var l = $0; l.isDefault = l.title == "GAME.EXE"; return l }
        late.chooseBestSound(year: 1994, hasMT32: true)
        #expect(late.launchers.first(where: \.isDefault)?.title == "GAME.EXE")
    }

    /// Games chosen under an older order are re-sorted (CD first), and the
    /// default moves only if it was still the old automatic pick.
    @Test func olderChoicesAreResortedKeepingThePlayersPick() {
        func info(defaultTitle: String) -> Gamebox.Info {
            var info = Gamebox.Info(name: "Out of This World (1991)")
            info.launchers = ["World Floppy w/ MT-32", "World CD w/ MT-32", "World Floppy w/ SoundBlaster",
                              "World CD w/ SoundBlaster"].map {
                Gamebox.Launcher(title: $0, dosPath: "C:\\run.bat", isDefault: $0 == defaultTitle, commands: ["world"])
            }
            info.soundChoiceVersion = 5
            return info
        }
        var automatic = info(defaultTitle: "World Floppy w/ MT-32")
        automatic.chooseBestSound(year: 1991, hasMT32: true)
        #expect(automatic.launchers.map(\.title).prefix(2) == ["World CD w/ MT-32", "World CD w/ SoundBlaster"])
        #expect(automatic.launchers.first(where: \.isDefault)?.title == "World CD w/ MT-32")
        var picked = info(defaultTitle: "World Floppy w/ SoundBlaster")
        picked.chooseBestSound(year: 1991, hasMT32: true)
        #expect(picked.launchers.first(where: \.isDefault)?.title == "World Floppy w/ SoundBlaster")
    }

    @Test func versionsAndSoundCardsAreRanked() {
        func best(_ titles: [String], year: Int, hasMT32: Bool = false) -> String? {
            var info = Gamebox.Info(name: "Game")
            info.launchers = titles.enumerated().map {
                Gamebox.Launcher(title: $1, dosPath: "C:\\run.bat", isDefault: $0 == 0, commands: ["game"])
            }
            info.chooseBestSound(year: year, hasMT32: hasMT32)
            return info.launchers.first(where: \.isDefault)?.title
        }
        #expect(best(["Play Shadow of the Comet Floppy", "Play Shadow of the Comet CD"], year: 1993)
                == "Play Shadow of the Comet CD")
        #expect(best(["Carmageddon", "Carmageddon HiRes", "Carmageddon 3DFX", "Carmageddon Splat Pack Hires",
                      "Network Multiplayer"], year: 1998) == "Carmageddon HiRes")
        #expect(best(["Crusader w/ SoundBlaster", "Crusader w/ Gravis Ultrasound"], year: 1995)
                == "Crusader w/ Gravis Ultrasound")
        #expect(best(["DOTT w/ Sound Canvas", "DOTT w/ MT-32", "DOTT w/ SoundBlaster"], year: 1993, hasMT32: true)
                == "DOTT w/ MT-32")
        #expect(best(["DOTT w/ Sound Canvas", "DOTT w/ MT-32", "DOTT w/ SoundBlaster"], year: 1993)
                == "DOTT w/ Sound Canvas")
        // The fuller version first, then the best sound within it
        var gk = Gamebox.Info(name: "Gabriel Knight")
        gk.launchers = ["GK w/ MT32", "GK w/ Sound Canvas", "GK CD w/ Sound Canvas", "GK w/ SoundBlaster",
                        "GK CD w/ MT32", "GK CD w/ SoundBlaster"].enumerated().map {
            Gamebox.Launcher(title: $1, dosPath: "C:\\run.bat", isDefault: $0 == 0, commands: ["sierra"])
        }
        gk.chooseBestSound(year: 1993, hasMT32: true)
        #expect(gk.launchers.map(\.title) == ["GK CD w/ MT32", "GK CD w/ Sound Canvas", "GK CD w/ SoundBlaster",
                                              "GK w/ MT32", "GK w/ Sound Canvas", "GK w/ SoundBlaster"])
    }

    /// Battle Chess's menu lists PC Speaker first; AdLib is better.
    @Test func soundChoicesAreOrderedBestFirst() {
        var info = Gamebox.Info(name: "Battle Chess (1988)")
        info.launchers = ["Battle Chess w/ PC Speaker", "Battle Chess w/ Adlib", "Network Multiplayer"]
            .enumerated().map { Gamebox.Launcher(title: $1, dosPath: "C:\\run.bat", isDefault: $0 == 0, commands: ["chess"]) }
            + [Gamebox.Launcher(title: "Chess", dosPath: "C:\\CHESS\\CHESS.EXE")]
        info.chooseBestSound(year: 1988, hasMT32: false)
        #expect(info.launchers.map(\.title) == ["Battle Chess w/ Adlib", "Battle Chess w/ PC Speaker",
                                                 "Network Multiplayer", "Chess"])
        #expect(info.launchers.first(where: \.isDefault)?.title == "Battle Chess w/ Adlib")
    }

    @Test func gamesSetUpForAGravisUltrasoundGetOne() throws {
        let folder = scratch.appending(path: "Albion", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "DRIVERS"), withIntermediateDirectories: true)
        try Data("ALBION".utf8).write(to: folder.appending(path: "ALBION.EXE"))
        try Data("DEVICE      Gravis UltraSound\nDRIVER      ULTRA.DIG\nIO_ADDR     240h\n".utf8)
            .write(to: folder.appending(path: "DRIVERS/DIG.INI"))
        let games = scratch.appending(path: "Games", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        let albion = try Gamebox.open(try GameImporter.makeGamebox(from: folder, inLibrary: games))
        #expect(albion.soundCardSettings() == ["gus gus": "true"])
        #expect(try albion.sessionArguments().contains("gus gus=true"))
    }

    @Test func namesPutTheArticleFirstAndSortWithoutIt() {
        #expect(GameNames.articleFirst("Dig, The (1995)") == "The Dig (1995)")
        #expect(GameNames.articleFirst("Elder Scrolls, The - Arena (1994)") == "The Elder Scrolls - Arena (1994)")
        #expect(GameNames.articleFirst("Bard's Tale, A") == "A Bard's Tale")
        #expect(GameNames.articleFirst("Doom (1993)") == "Doom (1993)")
        #expect(GameNames.articleFirst("Lemmings, Oh No! More (1991)") == "Lemmings, Oh No! More (1991)")
        #expect(GameNames.sortKey("The Dig (1995)") == "Dig (1995)")
        #expect(GameNames.fileName("Warcraft II: Tides of Darkness") == "Warcraft II - Tides of Darkness")
    }

    @Test func aFolderOfGamesIsImportedGameByGame() throws {
        let downloads = scratch.appending(path: "game-testing", directoryHint: .isDirectory)
        let year = downloads.appending(path: "1982", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: year, withIntermediateDirectories: true)
        for name in ["Alien (1982).zip", "Apple Panic (1982).zip"] {
            try Data("x".utf8).write(to: year.appending(path: name))
        }
        try Data("x".utf8).write(to: downloads.appending(path: "Digger (1983).zip"))
        let game = try makeGameFolder(named: "Keen")

        #expect(GameImporter.gamesInCollection(downloads).map(\.lastPathComponent)
                == ["Digger (1983).zip", "Alien (1982).zip", "Apple Panic (1982).zip"])
        #expect(GameImporter.gamesInCollection(year).count == 2)
        #expect(GameImporter.gamesInCollection(game) == [game])  // a game folder stays one game
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

        // Best sound first: MT-32 when this Mac has its ROMs, else Sound Blaster
        let expected = MT32Setup.isReady ? ["Boxing w/ MT-32", "Boxing w/ SoundBlaster"]
            : ["Boxing w/ SoundBlaster", "Boxing w/ MT-32"]
        #expect(gamebox.info.launchers.prefix(2).map(\.title) == expected)
        #expect(gamebox.defaultLauncher?.title == expected[0])
        #expect(gamebox.info.launchers.contains { $0.title == "Menu" })
        let mt32Launcher = try #require(gamebox.info.launchers.first { $0.title == "Boxing w/ MT-32" })
        let mt32 = try gamebox.sessionArguments(.launcher(mt32Launcher))
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
        let library = GameLibrary(location: root)
        defer { UserDefaults.standard.removeObject(forKey: "LibraryPath") }

        library.rename(library.games[0], to: "Commander Keen: Marooned on Mars")

        #expect(library.games.map(\.name) == ["Commander Keen: Marooned on Mars"])
        // Games at the top of the library were tidied into Games
        #expect(library.games[0].url.deletingLastPathComponent().lastPathComponent == "Games")
        #expect(library.games[0].url.lastPathComponent == "Commander Keen - Marooned on Mars.dosgame")
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
        let library = GameLibrary(location: root)
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

    /// Two games with the same ID (the same Boxer game converted twice):
    /// the second gets a new one; games with their own IDs keep them.
    @Test func duplicateIDsAreRepairedAndOthersKept() throws {
        let root = scratch.appending(path: "Library", directoryHint: .isDirectory)
        let games = root.appending(path: "Games")
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        let keen = try GameImporter.makeGamebox(from: try makeGameFolder(named: "Keen"), inLibrary: games)
        let copy = try GameImporter.makeGamebox(from: try makeGameFolder(named: "Copy"), inLibrary: games)
        let other = try GameImporter.makeGamebox(from: try makeGameFolder(named: "Other"), inLibrary: games)
        var duplicate = try Gamebox.open(copy)
        duplicate.info.id = try Gamebox.open(keen).id
        duplicate.info.dateAdded = Date().addingTimeInterval(60)  // added later
        try duplicate.save()
        let keenID = try Gamebox.open(keen).id, otherID = try Gamebox.open(other).id

        let library = GameLibrary(location: root)
        #expect(Set(library.games.map(\.id)).count == 3)
        #expect(try Gamebox.open(keen).id == keenID)
        #expect(try Gamebox.open(other).id == otherID)
        library.reload()
        #expect(Set(library.games.map(\.id)) == Set([keenID, otherID, try Gamebox.open(copy).id]))
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
