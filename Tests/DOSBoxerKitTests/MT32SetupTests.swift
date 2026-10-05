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

    /// archive.org's download: proper ROMs in one folder, and in another the
    /// same ROMs under chip names (".ic28") plus half-chip dumps.
    @Test func readsTheArchiveCollectionOnce() throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "mt32-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let pi = scratch.appending(path: "mt32pi", directoryHint: .isDirectory)
        let mame = scratch.appending(path: "MAME", directoryHint: .isDirectory)
        for folder in [pi, mame] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let control = Data((0..<131_072).map { UInt8($0 % 251) })
        let sound = Data((0..<524_288).map { UInt8($0 % 241) })
        try control.write(to: pi.appending(path: "ctrl_mt32_2_04.rom"))
        try sound.write(to: pi.appending(path: "pcm_mt32.rom"))
        try control.write(to: mame.appending(path: "mt32_2.0.4.ic28"))        // same ROM, chip name
        try Data(count: 32_768).write(to: mame.appending(path: "mt32_1.0.4.ic26.bin"))  // half a chip

        let found = try #require(MT32Setup.roms(in: scratch))
        #expect(Set(found.map(\.lastPathComponent)) == ["ctrl_mt32_2_04.rom", "pcm_mt32.rom"])
    }
}
