import Foundation

/// Marks a gamebox as being played on this Mac, so another Mac sharing the
/// library (through iCloud Drive, Dropbox, …) can warn before both write the
/// same saved games.
///
/// The marker is a small `InUse.json` inside the gamebox. A marker from this
/// same Mac is ignored: it can only be left over from a crash.
public enum GameboxPresence {
    static let fileName = "InUse.json"

    /// Markers older than this are treated as left over, not live.
    private static let staleAfter: TimeInterval = 12 * 60 * 60

    struct Marker: Codable {
        var computer: String
        var computerID: String
        var since: Date
    }

    /// The name of another Mac currently playing this game, if any.
    public static func otherComputerPlaying(_ gamebox: Gamebox) -> String? {
        guard let marker = read(gamebox),
              marker.computerID != thisComputerID,
              Date().timeIntervalSince(marker.since) < staleAfter else { return nil }
        return marker.computer
    }

    /// Records that this Mac is playing the game.
    public static func markInUse(_ gamebox: Gamebox) {
        guard isWritable(gamebox) else { return }
        let marker = Marker(computer: Host.current().localizedName ?? "another Mac",
                            computerID: thisComputerID, since: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(marker).write(to: markerURL(gamebox), options: .atomic)
    }

    /// Clears this Mac's marker (never another Mac's).
    public static func clearInUse(_ gamebox: Gamebox) {
        guard isWritable(gamebox), read(gamebox)?.computerID == thisComputerID else { return }
        try? FileManager.default.removeItem(at: markerURL(gamebox))
    }

    /// Read-only gameboxes (Boxer's) are never written to.
    private static func isWritable(_ gamebox: Gamebox) -> Bool {
        !gamebox.isReadOnly
    }

    private static func read(_ gamebox: Gamebox) -> Marker? {
        guard let data = try? Data(contentsOf: markerURL(gamebox)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Marker.self, from: data)
    }

    private static func markerURL(_ gamebox: Gamebox) -> URL {
        gamebox.url.appending(path: fileName)
    }

    private static var thisComputerID: String { ComputerIdentity.id }
}
