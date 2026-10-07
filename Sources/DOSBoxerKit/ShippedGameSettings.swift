import Foundation

/// Settings for particular games that ship with DOS Boxer
/// (`GameSettings.json`), found by playing them: the speed they need and
/// the program they start with (applied when a game is added), and settings
/// they need to run right (applied every time).
enum ShippedGameSettings {
    struct Entry: Decodable, Equatable {
        /// The game's name as collections name it, e.g. "Snipes (1982)".
        let name: String
        let launchBoxID: Int?
        /// DOSBox Staging's cpu_cycles, e.g. "300".
        let speed: String?
        /// The program it starts with, e.g. "C:\AUTOEXEC.BAT".
        let start: String?
        /// dosbox settings the game needs whenever it runs, e.g. larger sound
        /// blocks where speech crackles with DOSBox's usual ones (at the
        /// cost of a little sound delay, so only where needed); a player's
        /// own changes still win.
        var settings: [String: String]? = nil
    }

    private struct File: Decodable { let games: [Entry] }

    static let all: [Entry] = {
        guard let url = Bundle(for: GameLibrary.self).url(forResource: "GameSettings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.games
    }()

    /// The settings for `gamebox`: by its name, or by its LaunchBox entry
    /// when only one shipped game has that entry (LaunchBox sometimes files
    /// different games under one, like 1982's two Pac-Mans).
    static func entry(for gamebox: Gamebox, in entries: [Entry] = all) -> Entry? {
        let name = CoverArtFetcher.loose(gamebox.name)
        if let byName = entries.first(where: { CoverArtFetcher.loose($0.name) == name }) { return byName }
        guard let id = gamebox.info.launchBoxID else { return nil }
        let byID = entries.filter { $0.launchBoxID == id }
        return byID.count == 1 ? byID[0] : nil
    }

    /// Applies the shipped settings to a game that hasn't been played or
    /// changed yet. Returns true if anything changed.
    static func apply(to gamebox: inout Gamebox) -> Bool {
        guard gamebox.stats.launches == 0, let entry = entry(for: gamebox) else { return false }
        var changed = false
        if let speed = entry.speed, gamebox.info.settings["cpu cpu_cycles"] == nil {
            gamebox.info.settings["cpu cpu_cycles"] = speed
            changed = true
        }
        if let start = entry.start,
           let index = gamebox.info.launchers.firstIndex(where: { $0.commands == nil && $0.dosPath.caseInsensitiveCompare(start) == .orderedSame }),
           !gamebox.info.launchers[index].isDefault {
            for other in gamebox.info.launchers.indices { gamebox.info.launchers[other].isDefault = other == index }
            changed = true
        }
        return changed
    }
}
