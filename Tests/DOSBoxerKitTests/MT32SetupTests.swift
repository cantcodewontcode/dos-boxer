import Foundation
import Testing
@testable import DOSBoxerKit

@Suite(.serialized)
struct MT32SetupTests {
    @Test func needsAControlAndASoundROM() throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "mt32-\(UUID().uuidString)")
        let source = scratch.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        MT32Setup.folderOverride = scratch.appending(path: "ROMs", directoryHint: .isDirectory)
        defer { MT32Setup.folderOverride = nil; try? FileManager.default.removeItem(at: scratch) }

        try Data(count: 65_536).write(to: source.appending(path: "MT32_CONTROL.ROM"))
        try Data(count: 1234).write(to: source.appending(path: "notes.txt.rom"))   // wrong size: skipped
        #expect(try MT32Setup.install(from: [source]) == 1)
        #expect(MT32Setup.status() == .incomplete)
        #expect(MT32Setup.sessionArguments().isEmpty)

        try Data(count: 524_288).write(to: source.appending(path: "MT32_PCM.ROM"))
        #expect(try MT32Setup.install(from: [source.appending(path: "MT32_PCM.ROM")]) == 1)
        #expect(MT32Setup.status() == .ready(model: "MT-32"))
        #expect(MT32Setup.sessionArguments().last?.hasPrefix("mt32 romdir=") == true)

        try MT32Setup.removeAll()
        #expect(MT32Setup.status() == .notInstalled)
    }

    @Test func tellsROMDownloadsFromGames() throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "mt32-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        // A folder of ROMs (plus a readme), and a ZIP of it, as from archive.org
        let roms = scratch.appending(path: "Roland-MT-32-ROMs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: roms, withIntermediateDirectories: true)
        try Data(count: 65_536).write(to: roms.appending(path: "MT32_CONTROL.ROM"))
        try Data(count: 524_288).write(to: roms.appending(path: "MT32_PCM.ROM"))
        try Data("info".utf8).write(to: roms.appending(path: "readme.txt"))
        let zip = scratch.appending(path: "roms.zip")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", roms.path(percentEncoded: false), zip.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()
        // A game folder
        let game = scratch.appending(path: "Game", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: game.appending(path: "GAME.EXE"))

        #expect(MT32Setup.roms(in: roms)?.count == 2)
        #expect(MT32Setup.roms(in: zip)?.count == 2)
        #expect(MT32Setup.roms(in: roms.appending(path: "MT32_PCM.ROM"))?.count == 1)
        #expect(MT32Setup.roms(in: game) == nil)
    }
}
