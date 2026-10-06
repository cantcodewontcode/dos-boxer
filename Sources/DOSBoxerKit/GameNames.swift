import Foundation

/// How game names are written and sorted.
public enum GameNames {
    /// Collections file games by their main word: "Dig, The (1995)",
    /// "Elder Scrolls, The - Arena (1994)". DOS Boxer writes them the way
    /// people say them: "The Dig (1995)", "The Elder Scrolls - Arena (1994)".
    public static func articleFirst(_ name: String) -> String {
        name.replacingOccurrences(of: #"^(.+?), (The|A|An)((?: [-–:].*?)?(?: \(\d{3}[\dx]\))?)$"#,
                                  with: "$2 $1$3", options: .regularExpression)
    }

    /// What a name sorts by: without a leading "The", "A" or "An", so
    /// The Dig sorts under D.
    public static func sortKey(_ name: String) -> String {
        name.replacingOccurrences(of: #"^(The|A|An) "#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// The name a game is stored under on disk (no "/" or ":").
    static func fileName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")
            .replacingOccurrences(of: "  ", with: " ")
    }
}
