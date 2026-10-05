/// The kinds of game DOS Boxer knows: every genre the LaunchBox Games
/// Database uses (across all its platforms), alphabetically.
public enum GameGenres {
    public static let all = [
        "Action", "Adventure", "Beat 'em Up", "Board Game", "Casino", "Compilation",
        "Construction and Management Simulation", "Education", "Fighting", "Flight Simulator", "Horror",
        "Life Simulation", "MMO", "Music", "Party", "Pinball", "Platform", "Puzzle", "Quiz", "Racing",
        "Role-Playing", "Sandbox", "Shooter", "Sports", "Stealth", "Strategy", "Vehicle Simulation",
        "Visual Novel",
    ]
}

extension GameGenres {
    /// The known genre matching `name` loosely ("platform game" → "Platform",
    /// "role-playing video game" → "Role-Playing"), or nil.
    public static func standard(_ name: String) -> String? {
        var base = name.lowercased()
        for suffix in [" video game", " game"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        return all.first { $0.lowercased() == base || $0.lowercased() + "s" == base }
    }

    /// The known genre a free-form description belongs to: an exact match,
    /// or the known genre it mentions ("Point-and-click adventure" →
    /// "Adventure"). Nil if it mentions none.
    public static func closest(_ description: String) -> String? {
        if let exact = standard(description) { return exact }
        let text = description.lowercased()
        return all.sorted { $0.count > $1.count }.first { text.contains($0.lowercased()) }
    }

    /// Genres for the text typed so far: those starting with it first, then
    /// those containing it.
    public static func matching(_ text: String, excluding: [String]) -> [String] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        let available = all.filter { !excluding.contains($0) }
        guard !query.isEmpty else { return available }
        let starts = available.filter { $0.lowercased().hasPrefix(query) }
        let contains = available.filter { !$0.lowercased().hasPrefix(query) && $0.lowercased().contains(query) }
        return starts + contains
    }
}
