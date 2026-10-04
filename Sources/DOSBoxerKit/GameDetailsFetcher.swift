import Foundation

/// Looks up a game's publisher, developer and genre on Wikidata (free to
/// use for anything, no account needed). Only empty details are filled in,
/// so anything typed by hand is kept.
public actor GameDetailsFetcher {
    public static let shared = GameDetailsFetcher()

    private static let api = "https://www.wikidata.org/w/api.php"
    private static let userAgent = "DOSBoxer/0.1 (https://github.com/cantcodewontcode/dos-boxer)"
    /// Don't ask Wikidata about the same game more than this often.
    static let recheckAfter: TimeInterval = 30 * 24 * 60 * 60

    public struct Details: Equatable, Sendable {
        public var publisher: String?
        public var developer: String?
        public var genre: String?
    }

    /// Fills in `gamebox`'s missing details. Returns true if anything changed.
    @discardableResult
    public func fillDetails(of gamebox: Gamebox) async -> Bool {
        let info = gamebox.info
        guard !gamebox.isReadOnly,
              info.publisher == nil || info.developer == nil || info.genre == nil,
              info.detailsCheckedAt.map({ Date().timeIntervalSince($0) > Self.recheckAfter }) ?? true
        else { return false }

        var found = await lookUp(title: Self.searchTitle(gamebox.title), year: gamebox.year)
        // "Warcraft II - Tides of Darkness" is "Warcraft II: Tides of Darkness"
        if found == nil, gamebox.title.contains(" - ") {
            let colon = gamebox.title.replacingOccurrences(of: " - ", with: ": ")
            found = await lookUp(title: Self.searchTitle(colon), year: gamebox.year)
        }
        // "Duke Nukem - Episode 1 - Shrapnel City": try the main title alone
        if found == nil, let main = gamebox.title.components(separatedBy: " - ").first,
           main != gamebox.title, main.count >= 3 {
            found = await lookUp(title: Self.searchTitle(main), year: gamebox.year)
        }
        var updated = gamebox
        updated.info.detailsCheckedAt = Date()
        if let found {
            updated.info.publisher = info.publisher ?? found.publisher
            updated.info.developer = info.developer ?? found.developer
            updated.info.genre = info.genre ?? found.genre
        }
        try? updated.save()
        return found != nil
    }

    /// Wikidata's details for the video game called `title` (from `year`,
    /// if known), or nil.
    func lookUp(title: String, year: Int?) async -> Details? {
        struct Search: Decodable {
            struct Result: Decodable { let id: String; let description: String? }
            let search: [Result]
        }
        guard let results = await get(Search.self, ["action": "wbsearchentities", "search": title,
                                                    "language": "en", "type": "item", "limit": "10"])?.search,
              let match = Self.bestMatch(results.map { ($0.id, $0.description ?? "") }, year: year)
        else { return nil }

        struct Entities: Decodable {
            struct Entity: Decodable {
                struct Claim: Decodable {
                    struct Snak: Decodable {
                        struct Value: Decodable { let value: Item? }
                        /// A link to another entry. Other kinds of value (text,
                        /// dates) decode as nil rather than failing the lot.
                        struct Item: Decodable {
                            let id: String?
                            private enum Keys: String, CodingKey { case id }
                            init(from decoder: Decoder) throws {
                                id = try? decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .id)
                            }
                        }
                        let datavalue: Value?
                    }
                    let mainsnak: Snak
                }
                struct Label: Decodable { let value: String }
                let claims: [String: [Claim]]?
                let labels: [String: Label]?
            }
            let entities: [String: Entity]
        }
        guard let claims = await get(Entities.self, ["action": "wbgetentities", "ids": match,
                                                     "props": "claims"])?.entities[match]?.claims
        else { return nil }
        func ids(_ property: String) -> [String] {
            (claims[property] ?? []).compactMap { $0.mainsnak.datavalue?.value?.id }
        }
        // At most two of each: ported games can list a dozen publishers
        let publishers = Array(ids("P123").prefix(2)), developers = Array(ids("P178").prefix(2))
        let genres = Array(ids("P136").prefix(2))
        let all = Array(Set(publishers + developers + genres))
        guard !all.isEmpty else { return nil }

        var labels: [String: String] = [:]
        for batch in stride(from: 0, to: all.count, by: 50).map({ Array(all[$0..<min($0 + 50, all.count)]) }) {
            let entities = await get(Entities.self, ["action": "wbgetentities", "ids": batch.joined(separator: "|"),
                                                     "props": "labels", "languages": "en"])?.entities ?? [:]
            for (id, entity) in entities {
                if let label = entity.labels?["en"]?.value { labels[id] = label }
            }
        }
        func names(_ ids: [String]) -> String? {
            let found = ids.compactMap { labels[$0] }
            return found.isEmpty ? nil : found.joined(separator: ", ")
        }
        let genre = names(genres).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return Details(publisher: names(publishers), developer: names(developers), genre: genre)
    }

    /// The search result that's a video game, preferring the right year.
    static func bestMatch(_ results: [(id: String, description: String)], year: Int?) -> String? {
        // "1991 video game", "real-time strategy game…", but not series,
        // demos, or board and card games
        let excluded = ["series", "demo", "board game", "card game", "game show", "tabletop"]
        let games = results.filter { result in
            let description = result.description.lowercased()
            return description.range(of: #"\bgame\b"#, options: .regularExpression) != nil
                && !excluded.contains { description.contains($0) }
        }
        if let year, let exact = games.first(where: { $0.description.contains(String(year)) }) {
            return exact.id
        }
        // Without a year match, only trust a game that doesn't name another year
        return games.first { result in
            year == nil || result.description.range(of: #"\b(19|20)\d\d\b"#, options: .regularExpression) == nil
        }?.id
    }

    /// The title as people would search for it: no edition tags (SCI, CD…)
    /// or "Episode 1 - …" subtitles beyond the main name.
    static func searchTitle(_ title: String) -> String {
        title.replacingOccurrences(of: CoverArtFetcher.editionTagPattern, with: "",
                                   options: [.regularExpression, .caseInsensitive])
    }

    private func get<T: Decodable>(_ type: T.Type, _ parameters: [String: String]) async -> T? {
        var components = URLComponents(string: Self.api)!
        components.queryItems = (parameters.merging(["format": "json"]) { $1 })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
