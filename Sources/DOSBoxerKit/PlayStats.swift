import Foundation

/// How much a game has been played, for sorting by "Most Played" and
/// "Recently Played".
///
/// Each Mac keeps its own file in the gamebox (`Stats/<this Mac>.json`) and
/// the totals add them up, so Macs sharing a library through iCloud Drive or
/// Dropbox never write the same file.
public struct PlayStats: Codable, Sendable, Equatable {
    public var launches = 0
    public var lastPlayed: Date?
    public var secondsPlayed: TimeInterval = 0

    static let folderName = "Stats"

    /// Totals across every Mac that has played the game.
    static func load(for gameboxURL: URL) -> PlayStats {
        let folder = gameboxURL.appending(path: folderName, directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(PlayStats.self, from: Data(contentsOf: $0)) }
            .reduce(into: PlayStats()) { total, stats in
                total.launches += stats.launches
                total.secondsPlayed += stats.secondsPlayed
                total.lastPlayed = [total.lastPlayed, stats.lastPlayed].compactMap { $0 }.max()
            }
    }

    /// Records a session on this Mac. Read-only gameboxes (Boxer's) aren't
    /// written to.
    public static func recordSession(of gamebox: Gamebox, startedAt start: Date, endedAt end: Date = Date()) {
        guard !gamebox.isReadOnly else { return }
        let folder = gamebox.url.appending(path: folderName, directoryHint: .isDirectory)
        let file = folder.appending(path: "\(ComputerIdentity.id).json")
        var stats = (try? decoder.decode(PlayStats.self, from: Data(contentsOf: file))) ?? PlayStats()
        stats.launches += 1
        stats.lastPlayed = end
        stats.secondsPlayed += max(0, end.timeIntervalSince(start))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? encoder.encode(stats).write(to: file, options: .atomic)
        NotificationCenter.default.post(name: .gameSessionEnded, object: gamebox.url)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension Notification.Name {
    /// Posted (object: the gamebox URL) when a play session has been recorded.
    public static let gameSessionEnded = Notification.Name("DOSBoxerGameSessionEnded")
}

/// A stable, anonymous identifier for this Mac (shared by the in-use marker
/// and play stats).
enum ComputerIdentity {
    static let id: String = {
        let key = "ComputerID"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
}
