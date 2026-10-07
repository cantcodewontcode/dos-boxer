import CryptoKit
import Foundation
import Observation

/// Publishers, developers, genres and release dates for DOS games, from the
/// LaunchBox Games Database (gamesdb.launchbox-app.com).
///
/// LaunchBox offers its whole database as one daily-updated download and
/// welcomes other apps using it. DOS Boxer downloads it only when the person
/// agrees, keeps just the DOS games, and never ships or hosts the data.
@MainActor @Observable
public final class GameDetailsPack {
    public static let shared = GameDetailsPack()

    nonisolated public static let databaseURL = URL(string: "https://gamesdb.launchbox-app.com")!
    nonisolated static let downloadURL = URL(string: "https://gamesdb.launchbox-app.com/Metadata.zip")!

    public enum Step: Sendable {
        case downloading, extracting, preparing

        public var title: String {
            switch self {
            case .downloading: "Downloading…"
            case .extracting: "Extracting…"
            case .preparing: "Preparing…"
            }
        }
    }

    public enum State: Equatable {
        case notInstalled
        /// `progress` is nil when it can't be measured.
        case working(Step, progress: Double?)
        case installed(gameCount: Int, updated: Date)
        case failed(String)
    }

    public private(set) var state: State = .notInstalled
    /// Set after an update found nothing newer.
    public private(set) var isUpToDate = false
    private var job: Task<Void, Never>?

    public var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    private init() {
        if let file = Self.load() {
            state = .installed(gameCount: file.games.count, updated: file.sourceDate)
            // Made by an earlier DOS Boxer: get the details again for what's new
            if file.version ?? 1 < File.currentVersion { install() }
        }
    }

    // MARK: Install, update, remove

    /// Downloads the database and keeps its DOS games. With `onlyIfNewer`,
    /// first checks whether LaunchBox has a newer copy.
    public func install(onlyIfNewer: Bool = false) {
        guard !isWorking else { return }
        let previous = state
        isUpToDate = false
        state = .working(.downloading, progress: 0)
        job = Task {
            do {
                if onlyIfNewer, case .installed(_, let updated) = previous,
                   let latest = await Self.latestDate(), latest <= updated {
                    state = previous
                    isUpToDate = true
                    return
                }
                let file = try await Self.build { step, progress in
                    Task { @MainActor in
                        if self.isWorking { self.state = .working(step, progress: progress) }
                    }
                }
                try file.save()
                Self.cache = nil
                state = .installed(gameCount: file.games.count, updated: file.sourceDate)
                NotificationCenter.default.post(name: .gameDetailsPackChanged, object: nil)
            } catch is CancellationError {
                state = previous
            } catch {
                state = .failed("Couldn't get game details. Check your internet connection and try again.")
            }
        }
    }

    public func cancel() {
        job?.cancel()
    }

    /// Deletes the downloaded details. Details already added to games stay.
    public func remove() {
        cancel()
        try? FileManager.default.removeItem(at: Self.fileURL)
        Self.cache = nil
        isUpToDate = false
        state = .notInstalled
    }

    // MARK: Looking up games

    /// The details for a game called `name` (which may end in a year, like
    /// "Crystal Caves (1991)"), or nil.
    /// The game with this LaunchBox ID, if the details are downloaded.
    nonisolated public static func entry(launchBoxID: Int) -> Entry? {
        loadIndex()?.byID[launchBoxID]
    }

    /// The details for a game called `name` (which may end in a year). When
    /// several games share the name and there's no year to tell them apart,
    /// the one whose program is among `programs` (file names) wins.
    nonisolated public static func details(forName name: String, year: Int?, programs: Set<String> = []) -> Entry? {
        guard let index = loadIndex() else { return nil }
        // Named the way collections name it, year and all
        if let exact = index.byFolderName[CoverArtFetcher.loose(name)] { return exact }
        // eXoDOS names episodes "Duke Nukem - Episode 1 - Shrapnel City";
        // fall back to the main title
        var keys = CoverArtFetcher.lookupKeys(for: name)
        if let main = name.components(separatedBy: " - ").first, main != name, main.count >= 3 {
            keys += CoverArtFetcher.lookupKeys(for: main).filter { !keys.contains($0) }
        }
        for key in keys {
            guard let matches = index.byName[key], !matches.isEmpty else { continue }
            if let year, let exact = matches.first(where: { $0.year == year }) { return exact }
            if year == nil, matches.count > 1,
               let byProgram = matches.first(where: { $0.startupFile.map(programs.contains) ?? false }) {
                return byProgram
            }
            // Only trust a different year when it's the only game by that name
            if year == nil || matches.count == 1 { return matches[0] }
        }
        return nil
    }

    /// The game whose program or installer is one of `files`, recognized by
    /// its contents (so it works whatever the folder is called), or nil.
    nonisolated public static func details(forFilesIn folder: URL) -> Entry? {
        guard let index = loadIndex(),
              let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        else { return nil }
        for case let file as URL in files {
            guard let candidates = index.byFileName[file.lastPathComponent.uppercased()],
                  let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02X", $0) }.joined()
            if let match = candidates.first(where: { $0.startupMD5 == md5 || $0.setupMD5 == md5 }) {
                return match
            }
        }
        return nil
    }

    /// The game started by one of `programs` (file names, most likely
    /// first), when that program starts only one game LaunchBox knows: for
    /// copies whose files differ from the known release (shareware, demos)
    /// and whose folder name says little ("doom-box"). Batch files are
    /// skipped; their names are too often generic.
    nonisolated public static func details(forPrograms programs: [String]) -> Entry? {
        guard let index = loadIndex() else { return nil }
        for program in programs.map({ $0.uppercased() })
        where program.hasSuffix(".EXE") || program.hasSuffix(".COM") {
            let starting = (index.byFileName[program] ?? []).filter { $0.startupFile?.uppercased() == program }
            if starting.count == 1 { return starting[0] }
        }
        return nil
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var launchBoxID: Int
        public var name: String
        public var alternateNames: [String]?
        /// Folder names the game goes by in collections, e.g. "Hexxagon (1993)".
        public var folderNames: [String]?
        /// "1991-10-22", or just "1991".
        public var released: String?
        public var publisher: String?
        public var developer: String?
        public var genres: [String]?
        public var maxPlayers: Int?
        public var cooperative: Bool?
        /// ESRB, e.g. "T - Teen"; nil when not rated.
        public var ageRating: String?
        public var communityRating: Double?
        public var communityRatingCount: Int?
        public var overview: String?
        /// The program that starts the game, and the installer, with their
        /// MD5 checksums (uppercase hex), e.g. "WAR2.EXE".
        public var startupFile: String?
        public var startupMD5: String?
        public var setupFile: String?
        public var setupMD5: String?
        /// LaunchBox's front box art (or fan-made box art when there's no
        /// scan), a file name on images.launchbox-app.com.
        public var boxFront: String?

        public var boxFrontURL: URL? {
            boxFront.flatMap { URL(string: "https://images.launchbox-app.com/" + $0) }
        }

        public var year: Int? { released.flatMap { Int($0.prefix(4)) } }

        /// Copies these details into `info`, keeping anything already there.
        public func fill(_ info: inout Gamebox.Info) {
            info.launchBoxID = launchBoxID
            info.released = info.released ?? released
            info.publisher = info.publisher ?? publisher
            info.developer = info.developer ?? developer
            if info.genreList.isEmpty, let genres { info.setGenres(genres) }
            info.maxPlayers = info.maxPlayers ?? maxPlayers
            info.cooperative = info.cooperative ?? cooperative
            info.ageRating = info.ageRating ?? ageRating
            info.communityRating = communityRating ?? info.communityRating
            info.communityRatingCount = communityRatingCount ?? info.communityRatingCount
            info.overview = info.overview ?? overview
        }
    }

    // MARK: Storage

    struct File: Codable {
        /// 2 added the folder names games are known by.
        /// 2 added the folder names games are known by; 3 box art; 4 fan art.
        static let currentVersion = 4
        var version: Int? = currentVersion
        /// When LaunchBox last updated its database.
        var sourceDate: Date
        var games: [Entry]

        func save() throws {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: fileURL, options: .atomic)
        }
    }

    nonisolated static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "DOS Boxer/GameDetails.json")
    }

    nonisolated static func load() -> File? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }

    struct Index {
        /// Keyed by a loose form of each of their names.
        var byName: [String: [Entry]] = [:]
        /// Keyed by a loose form of their folder names (exact matches).
        var byFolderName: [String: Entry] = [:]
        /// Keyed by their program's and installer's file names.
        var byFileName: [String: [Entry]] = [:]
        var byID: [Int: Entry] = [:]
    }
    nonisolated(unsafe) private static var cache: Index?
    nonisolated private static let cacheLock = NSLock()

    nonisolated private static func loadIndex() -> Index? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cache { return cache }
        guard let file = load() else { return nil }
        var index = Index()
        for game in file.games {
            index.byID[game.launchBoxID] = game
            for name in [game.name] + (game.alternateNames ?? []) {
                index.byName[CoverArtFetcher.loose(name), default: []].append(game)
            }
            for folder in game.folderNames ?? [] {
                index.byFolderName[CoverArtFetcher.loose(folder)] = game
            }
            for file in [game.startupFile, game.setupFile].compactMap({ $0 }) {
                index.byFileName[file.uppercased(), default: []].append(game)
            }
        }
        cache = index
        return index
    }

    // MARK: Building

    nonisolated private static func latestDate() async -> Date? {
        var request = URLRequest(url: downloadURL)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (response as? HTTPURLResponse).flatMap(lastModified)
    }

    nonisolated private static func lastModified(_ response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Last-Modified") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }

    nonisolated private static func build(
        report: @escaping @Sendable (Step, Double?) -> Void
    ) async throws -> File {
        let work = FileManager.default.temporaryDirectory.appending(path: "DOSBoxerGameDetails-\(UUID())")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // Download
        let delegate = DownloadProgress { report(.downloading, $0) }
        let (downloaded, response) = try await URLSession.shared.download(from: downloadURL, delegate: delegate)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let zip = work.appending(path: "Metadata.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)
        try Task.checkCancellation()

        // Extract just the games list
        report(.extracting, nil)
        let unzip = Process()
        unzip.executableURL = URL(filePath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-q", zip.path(percentEncoded: false), "Metadata.xml", "Files.xml", "-d",
                           work.path(percentEncoded: false)]
        try await withTaskCancellationHandler {
            try unzip.run()
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    unzip.waitUntilExit()
                    continuation.resume()
                }
            }
        } onCancel: { unzip.terminate() }
        try Task.checkCancellation()
        guard unzip.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        try? FileManager.default.removeItem(at: zip)

        // Keep the DOS games
        report(.preparing, nil)
        let xml = work.appending(path: "Metadata.xml")
        guard let stream = InputStream(url: xml) else { throw CocoaError(.fileReadNoSuchFile) }
        let reader = MetadataReader()
        let parser = XMLParser(stream: stream)
        parser.delegate = reader
        guard parser.parse() else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        try Task.checkCancellation()

        var games = reader.games
        for index in games.indices {
            if let names = reader.alternateNames[reader.ids[index]] {
                games[index].alternateNames = names
            }
            games[index].boxFront = reader.boxFronts[reader.ids[index]]?.file
        }
        // Folder names games are known by in collections, e.g. "Hexxagon (1993)"
        if let files = InputStream(url: work.appending(path: "Files.xml")) {
            let folders = FolderNamesReader()
            let parser = XMLParser(stream: files)
            parser.delegate = folders
            if parser.parse() {
                for index in games.indices {
                    games[index].folderNames = folders.names[games[index].name]
                }
            }
        }
        return File(sourceDate: lastModified(http) ?? Date(), games: games)
    }
}

extension Notification.Name {
    /// Posted when game details were downloaded or updated.
    public static let gameDetailsPackChanged = Notification.Name("DOSBoxerGameDetailsPackChanged")
}

/// Reports download progress (0…1).
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let report: @Sendable (Double) -> Void

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

/// Reads LaunchBox's Files.xml: the folder names of MS-DOS games in
/// collections, by LaunchBox game name.
private final class FolderNamesReader: NSObject, XMLParserDelegate {
    var names: [String: [String]] = [:]
    private var fields: [String: String]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "File" { fields = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if fields != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        guard var current = fields else { return }
        if element == "File" {
            if current["Platform"] == "MS-DOS", let file = current["FileName"], let game = current["GameName"] {
                names[game, default: []].append(file)
            }
            fields = nil
        } else {
            current[element] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            fields = current
        }
        text = ""
    }
}

/// Reads LaunchBox's Metadata.xml, keeping MS-DOS games and every
/// alternate name (matched to the games afterwards).
private final class MetadataReader: NSObject, XMLParserDelegate {
    var games: [GameDetailsPack.Entry] = []
    /// LaunchBox's ID for each of `games`.
    var ids: [String] = []
    var alternateNames: [String: [String]] = [:]
    /// The best front box art per LaunchBox ID, with how well its region fits.
    var boxFronts: [String: (file: String, rank: Int)] = [:]

    private var fields: [String: String]?
    private var record: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "Game" || element == "GameAlternateName" || element == "GameImage" {
            record = element
            fields = [:]
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if fields != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        guard var current = fields else { return }
        if element == record {
            finish(current)
            fields = nil
            record = nil
        } else {
            current[element] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            fields = current
        }
        text = ""
    }

    private func finish(_ f: [String: String]) {
        func value(_ key: String) -> String? { f[key].flatMap { $0.isEmpty ? nil : $0 } }
        if record == "GameImage" {
            // Real box scans first, fan-made box art when there's none
            let type = value("Type")
            guard type == "Box - Front" || type == "Fanart - Box - Front",
                  let id = value("DatabaseID"), let file = value("FileName") else { return }
            // English-speaking releases first
            var rank = switch value("Region") {
            case nil, "North America", "United States": 0
            case "World", "United Kingdom", "Europe", "Australia", "Canada": 1
            default: 2
            }
            if type == "Fanart - Box - Front" { rank += 10 }
            if rank < boxFronts[id]?.rank ?? .max { boxFronts[id] = (file, rank) }
            return
        }
        if record == "GameAlternateName" {
            if let id = value("DatabaseID"), let name = value("AlternateName") {
                alternateNames[id, default: []].append(name)
            }
            return
        }
        guard value("Platform") == "MS-DOS", let name = value("Name"),
              let id = value("DatabaseID"), let launchBoxID = Int(id) else { return }
        let genres = value("Genres")?.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // Only the file name; some include a folder
        func fileName(_ key: String) -> String? {
            value(key)?.components(separatedBy: "\\").last?.uppercased()
        }
        games.append(.init(launchBoxID: launchBoxID, name: name,
                           released: value("ReleaseDate").map { String($0.prefix(10)) } ?? value("ReleaseYear"),
                           publisher: value("Publisher"), developer: value("Developer"),
                           genres: genres?.isEmpty == false ? genres : nil,
                           maxPlayers: value("MaxPlayers").flatMap(Int.init),
                           cooperative: value("Cooperative") == "true" ? true : nil,
                           ageRating: value("ESRB").flatMap { $0 == "Not Rated" ? nil : $0 },
                           communityRating: value("CommunityRating").flatMap(Double.init),
                           communityRatingCount: value("CommunityRatingCount").flatMap(Int.init),
                           overview: value("Overview"),
                           startupFile: fileName("StartupFile"), startupMD5: value("StartupMD5")?.uppercased(),
                           setupFile: fileName("SetupFile"), setupMD5: value("SetupMD5")?.uppercased()))
        ids.append(id)
    }
}
