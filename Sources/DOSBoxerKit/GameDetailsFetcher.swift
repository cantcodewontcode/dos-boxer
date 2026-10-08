import Foundation

/// Fills in a game's publisher, developer and genre: from the downloaded
/// LaunchBox details when it's there, otherwise from Wikidata (free to use
/// for anything, no account needed). Only empty details are filled in, so
/// anything typed by hand is kept.
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

    /// Looks an unmatched game up by its current name and files (Find Game
    /// Details), including one whose details were forgotten. Returns true
    /// if anything was found.
    public func findDetails(of gamebox: Gamebox) async -> Bool {
        guard !gamebox.isReadOnly, gamebox.info.launchBoxID == nil else { return false }
        var retrying = gamebox
        retrying.info.noDetails = nil
        retrying.info.detailsCheckedAt = nil
        try? retrying.save()
        return await fillDetails(of: retrying)
    }

    /// Whether `gamebox` was matched to a different game than the one its
    /// name is exactly a collection's name for.
    nonisolated static func isMismatched(_ gamebox: Gamebox) -> Bool {
        guard let id = gamebox.info.launchBoxID,
              let exact = GameDetailsPack.details(forFolderName: gamebox.name) else { return false }
        return exact.launchBoxID != id
    }

    /// Fills in `gamebox`'s missing details. Returns true if anything changed.
    @discardableResult
    public func fillDetails(of gamebox: Gamebox) async -> Bool {
        var gamebox = gamebox
        guard !gamebox.isReadOnly else { return false }
        // Matched to another game by a shared program (Sierra's SIERRA.COM
        // made Space Quest III Leisure Suit Larry III) although its name is
        // exactly a collection's name for this one: start over
        if Self.isMismatched(gamebox) {
            gamebox.info.clearDetails()
            if let cover = gamebox.coverURL { try? FileManager.default.removeItem(at: cover) }
            try? gamebox.save()
            gamebox = Gamebox(url: gamebox.url, info: gamebox.info)
        }
        let info = gamebox.info
        // Matched before genres were standardized: take LaunchBox's over the
        // older free-text one
        if let id = info.launchBoxID {
            guard info.genres == nil, info.genre != nil,
                  let genres = GameDetailsPack.entry(launchBoxID: id)?.genres else { return false }
            var updated = gamebox
            updated.info.setGenres(genres)
            try? updated.save()
            return true
        }

        // Recognized by its programs: the name collections know it by
        let drives = gamebox.url.appending(path: "Drives")
        // Named exactly as a collection names a game: the strongest evidence.
        // Programs can be shared (Sierra's SIERRA.COM is the same file in
        // several games, and LaunchBox lists it for only one)
        let byFiles = GameDetailsPack.details(forFolderName: gamebox.name)
            ?? GameDetailsPack.details(forFilesIn: drives)
        var recognized = GameFingerprints.collectionName(forFilesIn: drives)
        let recognizedEntry = recognized.flatMap { GameDetailsPack.details(forName: $0, year: nil) }
        // A program shared with another game (a sound driver) can point the
        // fingerprint at the wrong one; the game's own start program wins
        if let byFiles, let recognizedEntry, recognizedEntry.launchBoxID != byFiles.launchBoxID {
            recognized = nil
        }

        // The downloaded LaunchBox details: by the game's files, then its name
        if let entry = byFiles
            ?? (recognized == nil ? nil : recognizedEntry)
            ?? GameDetailsPack.details(forName: gamebox.name, year: gamebox.year,
                                       programs: Self.programNames(in: gamebox))
            ?? GameDetailsPack.details(forPrograms: info.launchers.filter { $0.commands == nil }
                .map { $0.dosPath.components(separatedBy: "\\").last ?? "" }) {
            var updated = gamebox
            // Recognized for the first time: take its proper name ("dukem1"
            // becomes "Duke Nukem - Episode 1 - Shrapnel City (1991)"). The
            // name collections use is the familiar one (LaunchBox's can be
            // a release's odd official title, like "Duke Nukum"); LaunchBox's
            // name with the year otherwise
            let year = entry.year ?? gamebox.year
            let canonical = recognized ?? entry.folderNames?.first
                ?? entry.name + (year.map { " (\($0))" } ?? "")
            updated.info.name = GameNames.articleFirst(canonical)
            entry.fill(&updated.info)
            // Now matched, shipped settings can be found by LaunchBox entry
            _ = ShippedGameSettings.apply(to: &updated)
            // A game that hasn't been played yet starts with the program
            // LaunchBox knows starts it
            if gamebox.stats.launches == 0, let startup = entry.startupFile,
               let launcher = updated.info.launchers.first(where: {
                   $0.commands == nil && $0.dosPath.uppercased().hasSuffix("\\" + startup) }) {
                for index in updated.info.launchers.indices {
                    updated.info.launchers[index].isDefault = updated.info.launchers[index].id == launcher.id
                }
            }
            try? updated.save()
            return true
        }

        // Known, but not to LaunchBox (or its details aren't downloaded):
        // at least take the name collections know it by
        if let recognized, info.detailsCheckedAt == nil {
            let name = GameNames.articleFirst(recognized)
            if name != info.name {
                var renamed = gamebox
                renamed.info.name = name
                try? renamed.save()
                return true
            }
        }

        guard info.publisher == nil || info.developer == nil || info.genreList.isEmpty,
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
            // Only genres DOS Boxer knows, so they match everywhere else
            let genres = (found.genre ?? "").components(separatedBy: ", ").compactMap(GameGenres.standard)
            if info.genreList.isEmpty, !genres.isEmpty { updated.info.setGenres(genres) }
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

    /// The game's program file names, uppercased (e.g. "OREGON.EXE").
    static func programNames(in gamebox: Gamebox) -> Set<String> {
        let drives = gamebox.url.appending(path: "Drives")
        guard let files = FileManager.default.enumerator(at: drives, includingPropertiesForKeys: nil) else { return [] }
        var names = Set<String>()
        for case let file as URL in files where ["exe", "com", "bat"].contains(file.pathExtension.lowercased()) {
            names.insert(file.lastPathComponent.uppercased())
        }
        return names
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
