import Foundation

/// A hand-built list of games, like a playlist: "Sierra Adventures",
/// "Played With Dad"…
public struct GameCollection: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    /// In the order games were added.
    public var gameIDs: [UUID] = []

    public init(name: String) {
        self.name = name
    }
}

/// Collections live in one small file at the top of the library
/// (`Collections.json`), so they travel and sync with it.
enum GameCollectionsFile {
    static let fileName = "Collections.json"

    static func load(from library: URL) -> [GameCollection] {
        guard let data = try? Data(contentsOf: library.appending(path: fileName)) else { return [] }
        return (try? JSONDecoder().decode([GameCollection].self, from: data)) ?? []
    }

    static func save(_ collections: [GameCollection], to library: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(collections).write(to: library.appending(path: fileName), options: .atomic)
    }
}
