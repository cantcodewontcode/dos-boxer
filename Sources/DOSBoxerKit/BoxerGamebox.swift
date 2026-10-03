import Foundation

/// Reads original Boxer gameboxes (`.boxer`) so they can be played and
/// converted. Boxer's layout:
///
///     X-COM.boxer/
///       Game Info.plist     BXDefaultProgramPath, BXGameIdentifier, …
///       C.harddisk/         drive folders, named <letter or label>.<kind>
///       D.cdrom/            (very old gameboxes keep drive C's files at the root)
///       Icon\r              custom Finder icon (box art)
///
/// The package itself is never modified; writes go to DOS Boxer's own
/// folder in Application Support.
enum BoxerGamebox {
    static func open(_ url: URL) throws -> Gamebox {
        let fileManager = FileManager.default
        let plist = (try? Data(contentsOf: url.appending(path: "Game Info.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]

        var info = Gamebox.Info(name: url.deletingPathExtension().lastPathComponent)
        if let identifier = plist["BXGameIdentifier"] as? String {
            info.id = stableUUID(from: identifier)
        }

        // Drive folders, in the order Boxer would assign letters
        let entries = (try? fileManager.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []
        var nextLetter: Character = "D"
        var folderForLetter: [String: String] = [:]
        for entry in entries.sorted() {
            let ext = (entry as NSString).pathExtension.lowercased()
            let kind: Gamebox.Drive.Kind
            switch ext {
            case "harddisk": kind = .hardDisk
            case "cdrom": kind = .cdROM
            case "floppy": kind = .floppy
            default: continue
            }
            let stem = (entry as NSString).deletingPathExtension.uppercased()
            var letter = stem.count == 1 && stem.first!.isLetter ? stem : ""
            if letter.isEmpty {
                letter = String(nextLetter)
                nextLetter = Character(UnicodeScalar(nextLetter.asciiValue! + 1))
            }
            info.drives.append(Gamebox.Drive(letter: letter, kind: kind, path: entry))
            folderForLetter[letter] = entry
        }
        // Old-style gamebox: the package root is drive C
        if !info.drives.contains(where: { $0.letter == "C" }) {
            info.drives.insert(Gamebox.Drive(letter: "C", kind: .hardDisk, path: "."), at: 0)
            folderForLetter["C"] = "."
        }

        if let programPath = plist["BXDefaultProgramPath"] as? String,
           let launcher = launcher(forRelativePath: programPath, drives: folderForLetter) {
            info.launchers = [launcher]
        }

        var gamebox = Gamebox(url: url, info: info)
        gamebox.externalSavesURL = URL.applicationSupportDirectory
            .appending(path: "DOS Boxer/Boxer Gamebox Saves/\(info.id.uuidString)", directoryHint: .isDirectory)
        return gamebox
    }

    /// Turns "C.harddisk/XCOMDEMO/XCOM.BAT" into C:\XCOMDEMO\XCOM.BAT.
    private static func launcher(forRelativePath path: String, drives: [String: String]) -> Gamebox.Launcher? {
        let parts = path.split(separator: "/").map(String.init)
        for (letter, folder) in drives where folder != "." {
            if parts.first == folder {
                return makeLauncher(letter: letter, rest: Array(parts.dropFirst()))
            }
        }
        return drives["C"] == "." ? makeLauncher(letter: "C", rest: parts) : nil
    }

    private static func makeLauncher(letter: String, rest: [String]) -> Gamebox.Launcher? {
        guard let program = rest.last else { return nil }
        let title = (program as NSString).deletingPathExtension.capitalized
        return Gamebox.Launcher(title: title, dosPath: "\(letter):\\" + rest.joined(separator: "\\"), isDefault: true)
    }

    /// The same Boxer game always maps to the same DOS Boxer ID.
    private static func stableUUID(from identifier: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in identifier.utf8.enumerated() {
            bytes[index % 16] = bytes[index % 16] &* 31 &+ byte
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
