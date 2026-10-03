import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A DOS Boxer gamebox: a package folder ending in `.dosgame`.
    public static let dosGame = UTType(exportedAs: "com.dosboxer.game", conformingTo: .package)
    /// An original Boxer gamebox (`.boxer`), which we can open and convert.
    public static let boxerGame = UTType(importedAs: "net.washboardabs.boxer-game-package", conformingTo: .package)
}

/// A game and everything it needs, kept together in one package:
///
///     Crystal Caves.dosgame/
///       Game.json        name, drives, launchers, settings
///       Drives/C/        the game's files (never written to while playing)
///       Saves/C/         everything the game writes: saves, configs, high scores
///       Cover.jpeg       box art (optional)
///
/// Games write into `Saves` through an overlay drive, so the original files
/// stay pristine and "revert to original" is just emptying `Saves`.
public struct Gamebox: Sendable, Identifiable {
    public var url: URL
    public var info: Info
    /// Where writes go when they can't live inside the package (original
    /// Boxer gameboxes, which we only read). Nil means `<package>/Saves`.
    var externalSavesURL: URL?

    public var id: UUID { info.id }
    public var name: String { info.name }

    /// What's stored in `Game.json`.
    public struct Info: Codable, Sendable {
        public var formatVersion = 1
        public var id = UUID()
        public var name: String
        public var drives: [Drive] = []
        public var launchers: [Launcher] = []
        /// dosbox settings as "section key" → value, e.g. "cpu cycles" → "max".
        public var settings: [String: String] = [:]
        /// Close the game when its program ends, instead of leaving people
        /// at a DOS prompt. Missing means yes.
        public var quitsWhenGameEnds: Bool?

        public var closesWhenGameEnds: Bool { quitsWhenGameEnds ?? true }
    }

    public struct Drive: Codable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable { case hardDisk, cdROM, floppy }
        /// "C", "D", …
        public var letter: String
        public var kind: Kind
        /// Path inside the gamebox, e.g. "Drives/C".
        public var path: String
    }

    /// A program people start the game with.
    public struct Launcher: Codable, Sendable, Hashable, Identifiable {
        public var id = UUID()
        public var title: String
        /// DOS path including the drive, e.g. `C:\CC1\CC1.EXE`.
        public var dosPath: String
        public var isDefault = false
    }

    // MARK: Files

    static let infoFileName = "Game.json"
    static let drivesFolder = "Drives"
    static let savesFolder = "Saves"
    static let coverBaseName = "Cover"

    public var savesURL: URL {
        externalSavesURL ?? url.appending(path: Self.savesFolder, directoryHint: .isDirectory)
    }

    public var coverURL: URL? {
        ["jpeg", "jpg", "png", "heic"]
            .map { url.appending(path: "\(Self.coverBaseName).\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    public var defaultLauncher: Launcher? {
        info.launchers.first(where: \.isDefault) ?? info.launchers.first
    }

    /// Opens a gamebox: a `.dosgame` package, or an original Boxer `.boxer`
    /// package (read through an adapter; it isn't modified until saved).
    public static func open(_ url: URL) throws -> Gamebox {
        if url.pathExtension.lowercased() == "boxer" {
            return try BoxerGamebox.open(url)
        }
        let data = try Data(contentsOf: url.appending(path: infoFileName))
        let info = try JSONDecoder().decode(Info.self, from: data)
        return Gamebox(url: url, info: info)
    }

    /// Writes `Game.json`.
    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: url.appending(path: Self.infoFileName), options: .atomic)
    }

    /// Discards everything the game has written (saves, settings it changed),
    /// returning it to how it was installed.
    public func revertToOriginal() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: savesURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: savesURL)
        }
    }

    // MARK: Session

    /// What a session should start with.
    public enum Start: Sendable, Hashable {
        /// The default launcher.
        case game
        case launcher(Launcher)
        /// A DOS prompt with the game's drives mounted.
        case prompt
    }

    /// dosbox arguments that mount the drives (with saves overlaid) and then
    /// run the game, a specific launcher, or just give a prompt.
    public func sessionArguments(_ start: Start = .game) throws -> [String] {
        let fileManager = FileManager.default
        var mounts: [String] = []
        for drive in info.drives {
            let source = url.appending(path: drive.path).path(percentEncoded: false)
            switch drive.kind {
            case .hardDisk:
                let saves = savesURL.appending(path: drive.letter, directoryHint: .isDirectory)
                try fileManager.createDirectory(at: saves, withIntermediateDirectories: true)
                mounts.append("@MOUNT \(drive.letter) \"\(source)\" >NUL")
                mounts.append("@MOUNT -t overlay \(drive.letter) \"\(saves.path(percentEncoded: false))\" >NUL")
            case .cdROM:
                mounts.append("@MOUNT \(drive.letter) \"\(source)\" -t cdrom >NUL")
            case .floppy:
                mounts.append("@MOUNT \(drive.letter) \"\(source)\" -t floppy >NUL")
            }
        }
        let settings = info.settings.sorted { $0.key < $1.key }.flatMap { ["--set", "\($0.key)=\($0.value)"] }
        let program: Launcher? = switch start {
        case .game: defaultLauncher
        case .launcher(let launcher): launcher
        case .prompt: nil
        }
        let exitsAfterwards = program != nil && info.closesWhenGameEnds
        if program == nil, let drive = info.drives.first {
            mounts.append("@\(drive.letter):")
        }
        return settings + StartupScript.arguments(
            mounts: mounts,
            title: name,
            detail: program == nil ? "Type DIR to see the game's files."
                : exitsAfterwards ? "Starting the game…" : "When the game ends, you'll be back at the DOS prompt.",
            program: program?.dosPath,
            exitsAfterwards: exitsAfterwards)
    }
}
