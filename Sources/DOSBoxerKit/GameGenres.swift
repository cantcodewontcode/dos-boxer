/// The kinds of game DOS Boxer knows, as the LaunchBox Games Database names
/// them, most common first.
public enum GameGenres {
    public static let all = [
        "Action", "Adventure", "Shooter", "Strategy", "Puzzle", "Platform", "Sports", "Role-Playing",
        "Education", "Construction and Management Simulation", "Flight Simulator", "Racing", "Board Game",
        "Vehicle Simulation", "Fighting", "Casino", "Quiz", "Beat 'em Up", "Compilation", "Horror",
        "Life Simulation", "Pinball", "Stealth", "Sandbox", "Party", "Visual Novel", "Music",
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
}
