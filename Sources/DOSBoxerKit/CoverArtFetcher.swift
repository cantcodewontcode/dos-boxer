import Foundation

/// Finds box art online for games that didn't come with any.
///
/// Source: the community-maintained libretro-thumbnails DOS collection on
/// GitHub (the box art RetroArch shows). Its file names follow eXoDOS's game
/// names, e.g. "Duke Nukem - Episode 1 - Shrapnel City (1991).png", so most
/// games match by name. Art is downloaded into each gamebox, never bundled
/// with the app.
public actor CoverArtFetcher {
    public static let shared = CoverArtFetcher()

    private static let treeBase = "https://api.github.com/repos/libretro-thumbnails/DOS/git/trees/"
    private static let rootContentsURL = URL(string: "https://api.github.com/repos/libretro-thumbnails/DOS/contents/")!
    private static let imageBase = "https://raw.githubusercontent.com/libretro-thumbnails/DOS/master/Named_Boxarts/"
    /// The list of available art is refreshed at most this often.
    private static let indexMaxAge: TimeInterval = 7 * 24 * 60 * 60

    /// Available box art names (without ".png"), keyed by a loose form of the
    /// name for forgiving matches.
    private var index: [String: String]?

    private var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "DOS Boxer/CoverArtIndex.json")
    }

    /// Downloads box art for `gamebox` if it has none. Returns true if a
    /// cover was saved.
    @discardableResult
    public func fetchCover(for gamebox: Gamebox, evenIfRemoved: Bool = false) async -> Bool {
        guard gamebox.coverURL == nil,
              evenIfRemoved || gamebox.info.noCover != true,
              gamebox.url.pathExtension.lowercased() == "dosgame",
              let name = await bestMatch(for: gamebox.name) else { return false }

        let fileName = Self.libretroFileName(name) + ".png"
        guard let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: Self.imageBase + encoded),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              // Some files named .png are really JPEGs; keep the true type
              let ext = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png"
                : data.starts(with: [0xFF, 0xD8, 0xFF]) ? "jpeg" : nil else { return false }
        do {
            try data.write(to: gamebox.url.appending(path: "\(Gamebox.coverBaseName).\(ext)"), options: .atomic)
            if gamebox.info.noCover == true {
                var updated = gamebox
                updated.info.noCover = nil
                try? updated.save()
            }
            return true
        } catch {
            return false
        }
    }

    /// The available art name that best fits `gameName`, if any.
    func bestMatch(for gameName: String) async -> String? {
        guard let index = await loadIndex() else { return nil }
        for candidate in Self.lookupKeys(for: gameName) {
            if let match = index[candidate] { return match }
        }
        return nil
    }

    // MARK: Matching

    /// Keys to try, most specific first: the full name, then without the
    /// year, then with a trailing ", The" moved to the front (or back).
    static func lookupKeys(for name: String) -> [String] {
        let withoutYear = name.replacingOccurrences(of: #"\s*\(\d{3}[\dx]\)\s*$"#, with: "",
                                                    options: .regularExpression)
        var variants = [name, withoutYear]
        for variant in [name, withoutYear] {
            if let range = variant.range(of: ", The", options: [.caseInsensitive]) {
                variants.append("The " + variant.replacingCharacters(in: range, with: ""))
            }
        }
        // Edition tags eXoDOS adds that cover collections usually leave out,
        // e.g. "Leisure Suit Larry 1 - … SCI (1991)"
        let year = name.range(of: #"\(\d{3}[\dx]\)\s*$"#, options: .regularExpression).map { String(name[$0]) }
        let untagged = withoutYear.replacingOccurrences(of: editionTagPattern, with: "",
                                                        options: [.regularExpression, .caseInsensitive])
        if untagged != withoutYear {
            if let year { variants.append("\(untagged) \(year)") }
            variants.append(untagged)
        }
        var seen = Set<String>()
        return variants.map(loose).filter { seen.insert($0).inserted }
    }

    /// Trailing edition and version words (one or more) before the year.
    static let editionTagPattern =
        #"(\s*[-–]?\s*\b(SCI|AGI|EGA|VGA|SVGA|CGA|Tandy|CD|CD-ROM|Floppy|Enhanced|Remake|Deluxe|Talkie|Special Edition|Collector'?s Edition|Shareware|Registered|v?\d+\.\d+[a-z]?)\b)+\s*$"#

    /// Lowercase letters and digits only, so punctuation and spacing
    /// differences don't matter.
    static func loose(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
            .map(Character.init))
    }

    /// libretro replaces characters that aren't allowed in file names with "_".
    static func libretroFileName(_ name: String) -> String {
        String(name.map { "&*/:`<>?\\|\"".contains($0) ? "_" : $0 })
    }

    // MARK: Index

    private struct CachedIndex: Codable {
        var fetched: Date
        var names: [String]
    }

    private func loadIndex() async -> [String: String]? {
        if let index { return index }
        var names: [String]?
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(CachedIndex.self, from: data),
           Date().timeIntervalSince(cached.fetched) < Self.indexMaxAge {
            names = cached.names
        } else if let fresh = await downloadIndex() {
            names = fresh
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? JSONEncoder().encode(CachedIndex(fetched: Date(), names: fresh)).write(to: cacheURL)
        } else if let data = try? Data(contentsOf: cacheURL),
                  let stale = try? JSONDecoder().decode(CachedIndex.self, from: data) {
            names = stale.names  // offline: an old list beats none
        }
        guard let names else { return nil }

        var built: [String: String] = [:]
        // Prefer names with a year when two only differ by it
        for name in names.sorted(by: { $0.count > $1.count }) where built[Self.loose(name)] == nil {
            built[Self.loose(name)] = name
        }
        for name in names {
            let withoutYear = Self.loose(name.replacingOccurrences(of: #"\s*\(\d{3}[\dx]\)\s*$"#, with: "",
                                                                   options: .regularExpression))
            if built[withoutYear] == nil { built[withoutYear] = name }
        }
        index = built
        return built
    }

    /// Lists the collection's box art through GitHub's API (two requests).
    private func downloadIndex() async -> [String]? {
        struct Entry: Decodable { let name: String; let sha: String }
        struct Tree: Decodable { let tree: [Item]; struct Item: Decodable { let path: String } }
        guard let (rootData, _) = try? await URLSession.shared.data(from: Self.rootContentsURL),
              let root = try? JSONDecoder().decode([Entry].self, from: rootData),
              let sha = root.first(where: { $0.name == "Named_Boxarts" })?.sha,
              let treeURL = URL(string: Self.treeBase + sha),
              let (treeData, _) = try? await URLSession.shared.data(from: treeURL),
              let tree = try? JSONDecoder().decode(Tree.self, from: treeData) else { return nil }
        return tree.tree.map(\.path).filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) }
    }
}
