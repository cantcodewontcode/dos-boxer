import AppKit
import Foundation
import Observation

/// The folder of gameboxes DOS Boxer manages, `~/DOSBoxer` by default.
///
/// The library is just a folder: one `.dosgame` package per game plus a small
/// `Library.json` marker. There's deliberately no database inside it, so it can
/// live in iCloud Drive, Dropbox or OneDrive without sync corrupting anything;
/// each game's own `Game.json` is the source of truth.
@MainActor
@Observable
public final class GameLibrary {
    public private(set) var rootURL: URL
    public private(set) var games: [Gamebox] = []
    /// Hand-built lists of games, shown in the sidebar.
    public private(set) var collections: [GameCollection] = []
    /// A game being copied into the library, shown as a placeholder card.
    public struct PendingImport: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
    }

    /// Games still being added, for progress UI.
    public private(set) var pendingImports: [PendingImport] = []

    /// A game just added that's already in the library, waiting for the
    /// person to choose what to do. Shown one at a time.
    public struct DuplicateImport: Identifiable, Sendable {
        public let id = UUID()
        public let added: Gamebox
        public let existing: Gamebox
    }
    public enum DuplicateChoice: Sendable { case replace, keepBoth, skip }
    public private(set) var duplicates: [DuplicateImport] = []
    public private(set) var lastError: String? {
        didSet { if let lastError { FileHandle.standardError.write(Data("DOS Boxer library: \(lastError)\n".utf8)) } }
    }

    /// What's stored in `Library.json`.
    struct Marker: Codable {
        var formatVersion = 1
        var id = UUID()
    }

    nonisolated static let markerFileName = "Library.json"
    private static let locationKey = "LibraryPath"

    /// The gameboxes, in their own folder so the library's top level stays
    /// tidy (just Games, Screenshots and Library.json).
    public var gamesURL: URL {
        rootURL.appending(path: "Games", directoryHint: .isDirectory)
    }

    /// Screenshots from every game, in one folder of the library.
    public var screenshotsURL: URL {
        rootURL.appending(path: "Screenshots", directoryHint: .isDirectory)
    }

    public static var defaultLocation: URL {
        URL.homeDirectory.appending(path: "DOSBoxer", directoryHint: .isDirectory)
    }

    /// Opens the library at `location`, or by default the one last used.
    /// (Tests pass a scratch folder, so they never touch a real library.)
    public init(location: URL? = nil) {
        let saved = UserDefaults.standard.string(forKey: Self.locationKey)
        rootURL = location ?? saved.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Self.defaultLocation
        reload()
        // Keep "Recently Played" and "Most Played" current
        NotificationCenter.default.addObserver(forName: .gameDetailsPackChanged, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookUpDetailsAgain() }
        }
        NotificationCenter.default.addObserver(forName: .gameSessionEnded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Switches to the library at `url`, creating it if needed.
    public func useLibrary(at url: URL) {
        rootURL = url
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: Self.locationKey)
        reload()
    }

    /// Re-reads the games in the library folder.
    public func reload() {
        do {
            try ensureExists()
            let fileManager = FileManager.default
            let entries = try fileManager.contentsOfDirectory(at: gamesURL, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles])
            collections = GameCollectionsFile.load(from: rootURL)
            // Games waiting on a duplicate question stay out of sight
            let waiting = Set(duplicates.map(\.added.url.standardizedFileURL))
            games = Self.withBASICPrograms(Self.withUniqueIDs(entries
                .filter { ["dosgame", "boxer"].contains($0.pathExtension.lowercased()) }
                .filter { !waiting.contains($0.standardizedFileURL) }
                .compactMap { try? Gamebox.open($0) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }))
            lastError = nil
            fetchMissingCovers()
            fetchMissingDetails()
        } catch {
            lastError = "Couldn't read the library at \(rootURL.path(percentEncoded: false)): \(error.localizedDescription)"
        }
    }

    // MARK: Cover art

    /// Games whose cover we've already looked for since launch.
    private var coverLookupsTried: Set<UUID> = []
    private var isFetchingCovers = false

    /// Looks online for box art for games without any, one at a time, each
    /// game at most once per launch.
    private func fetchMissingCovers() {
        guard !isFetchingCovers else { return }
        let missing = games.filter { $0.coverURL == nil && !coverLookupsTried.contains($0.id) }
        guard !missing.isEmpty else { return }
        isFetchingCovers = true
        missing.forEach { coverLookupsTried.insert($0.id) }
        Task {
            var foundAny = false
            for game in missing where await CoverArtFetcher.shared.fetchCover(for: game) {
                foundAny = true
            }
            isFetchingCovers = false
            // Reloading also picks up games added while we were busy
            if foundAny { reload() } else { fetchMissingCovers() }
        }
    }

    /// Games whose details (publisher, genres…) we've looked up
    /// since launch.
    private var detailLookupsTried: Set<UUID> = []
    private var isFetchingDetails = false

    /// Looks for missing details again, e.g. after game details were
    /// downloaded.
    public func lookUpDetailsAgain() {
        detailLookupsTried = []
        coverLookupsTried = []  // new details can bring box art
        fetchMissingDetails()
        fetchMissingCovers()
    }

    /// Fills in missing publishers, developers and genres, one game at a
    /// time.
    private func fetchMissingDetails() {
        guard !isFetchingDetails else { return }
        let missing = games.filter { game in
            !game.isReadOnly && !detailLookupsTried.contains(game.id)
                && (game.info.launchBoxID == nil || game.info.genres == nil && game.info.genre != nil)
        }
        guard !missing.isEmpty else { return }
        isFetchingDetails = true
        missing.forEach { detailLookupsTried.insert($0.id) }
        Task {
            var foundAny = false
            for game in missing where await GameDetailsFetcher.shared.fillDetails(of: game) {
                foundAny = true
                // Now matched, it may have box art of its own: look again
                coverLookupsTried.remove(game.id)
            }
            isFetchingDetails = false
            if foundAny { reload() } else { fetchMissingDetails() }
        }
    }

    /// Games whose box art is being looked for on request (their covers
    /// show a spinner).
    public private(set) var findingCovers: Set<Gamebox.ID> = []

    /// Looks online for `game`'s box art again, replacing nothing it has.
    /// Finding none isn't an error: the spinner stops and the cover stays
    /// as it was.
    public func findCoverArt(for game: Gamebox) {
        findingCovers.insert(game.id)
        Task {
            let started = Date()
            let found = await CoverArtFetcher.shared.fetchCover(for: game, evenIfRemoved: true)
            // Spin long enough to see that it looked
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.8 { try? await Task.sleep(for: .seconds(0.8 - elapsed)) }
            findingCovers.remove(game.id)
            if found { reload() }
        }
    }

    /// Makes the image at `imageURL` the game's cover.
    public func setCover(of game: Gamebox, to imageURL: URL) {
        let ext = imageURL.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "heic"].contains(ext), game.url.pathExtension.lowercased() == "dosgame" else {
            lastError = "Covers can be PNG, JPEG or HEIC images."
            return
        }
        do {
            if let old = game.coverURL { try FileManager.default.removeItem(at: old) }
            try FileManager.default.copyItem(at: imageURL, to: game.url.appending(path: "\(Gamebox.coverBaseName).\(ext)"))
            if game.info.noCover == true {
                var updated = game
                updated.info.noCover = nil
                try updated.save()
            }
            reload()
        } catch {
            lastError = "Couldn't use that image: \(error.localizedDescription)"
        }
    }

    /// Removes `game`'s cover and stops it being fetched again
    /// automatically (Find Cover Art or dropping an image brings one back).
    public func removeCover(of game: Gamebox) {
        guard game.url.pathExtension.lowercased() == "dosgame" else { return }
        do {
            if let cover = game.coverURL { try FileManager.default.removeItem(at: cover) }
            var updated = game
            updated.info.noCover = true
            try updated.save()
            reload()
        } catch {
            lastError = "Couldn't remove the cover: \(error.localizedDescription)"
        }
    }

    // MARK: Collections

    /// Makes a new, empty collection (with `games` in it, if given).
    @discardableResult
    public func createCollection(named name: String = "Untitled Collection", with games: [Gamebox] = []) -> GameCollection {
        var collection = GameCollection(name: name)
        collection.gameIDs = games.map(\.id)
        collections.append(collection)
        saveCollections()
        return collection
    }

    public func renameCollection(_ id: GameCollection.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = trimmed
        saveCollections()
    }

    public func deleteCollection(_ id: GameCollection.ID) {
        collections.removeAll { $0.id == id }
        saveCollections()
    }

    /// Adds games to a collection (each game once).
    public func add(_ games: [Gamebox.ID], toCollection id: GameCollection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        for game in games where !collections[index].gameIDs.contains(game) {
            collections[index].gameIDs.append(game)
        }
        saveCollections()
    }

    public func remove(_ game: Gamebox.ID, fromCollection id: GameCollection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].gameIDs.removeAll { $0 == game }
        saveCollections()
    }

    private func saveCollections() {
        do {
            try GameCollectionsFile.save(collections, to: rootURL)
        } catch {
            lastError = "Couldn't save your collections: \(error.localizedDescription)"
        }
    }

    // MARK: Game settings

    /// Changes `game`'s Game.json with `change` and reloads.
    public func update(_ game: Gamebox, _ change: (inout Gamebox.Info) -> Void) {
        guard !game.isReadOnly else {
            lastError = "Original Boxer gameboxes can't be changed. Add it to the library to make a DOS Boxer copy."
            return
        }
        var updated = game
        change(&updated.info)
        do {
            try updated.save()
            reload()
        } catch {
            lastError = "Couldn't save changes to \(game.name): \(error.localizedDescription)"
        }
    }

    public func toggleFavorite(_ game: Gamebox) {
        update(game) { $0.isFavorite = ($0.isFavorite == true) ? nil : true }
    }

    /// Makes `launcher` the program the game starts with.
    public func setDefaultLauncher(_ launcher: Gamebox.Launcher, of game: Gamebox) {
        update(game) { info in
            for index in info.launchers.indices {
                info.launchers[index].isDefault = info.launchers[index].id == launcher.id
            }
        }
    }

    // MARK: Renaming and deleting

    /// Gives `game` a new name: in its Game.json, and as its package's file
    /// name. Original Boxer gameboxes can't be renamed (we don't change them).
    public func rename(_ game: Gamebox, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != game.name else { return }
        guard game.url.pathExtension.lowercased() == "dosgame" else {
            lastError = "Original Boxer gameboxes can't be renamed. Add it to the library first to make a DOS Boxer copy."
            return
        }
        do {
            var renamed = game
            renamed.info.name = name
            try renamed.save()
            let fileName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let destination = game.url.deletingLastPathComponent().appending(path: "\(fileName).dosgame")
            if destination.path(percentEncoded: false).lowercased() != game.url.path(percentEncoded: false).lowercased(),
               !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.moveItem(at: game.url, to: destination)
            }
            reload()
        } catch {
            lastError = "Couldn't rename \(game.name): \(error.localizedDescription)"
            reload()
        }
    }

    /// Moves games (with their saved games) to the Trash.
    public func delete(_ games: [Gamebox]) {
        for game in games {
            do {
                try FileManager.default.trashItem(at: game.url, resultingItemURL: nil)
            } catch {
                lastError = "Couldn't move \(game.name) to the Trash: \(error.localizedDescription)"
            }
        }
        reload()
    }

    public func setFavorite(_ games: [Gamebox], _ favorite: Bool) {
        for game in games where !game.isReadOnly {
            var updated = game
            updated.info.isFavorite = favorite ? true : nil
            try? updated.save()
        }
        reload()
    }

    public func reportError(_ message: String) {
        lastError = message
    }

    public func dismissError() {
        lastError = nil
    }

    /// Discards everything `game` has written, returning it to how it was
    /// added to the library.
    public func revertToOriginal(_ game: Gamebox) {
        do {
            try game.revertToOriginal()
        } catch {
            lastError = "Couldn't revert \(game.name): \(error.localizedDescription)"
        }
    }

    /// Whether `folder` holds a DOS Boxer library.
    nonisolated public static func isLibrary(_ folder: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: folder.appending(path: markerFileName).path(percentEncoded: false))
            || fileManager.fileExists(atPath: folder.appending(path: "Games").path(percentEncoded: false))
    }

    /// Moves the whole library into `folder` (as a folder of the same name)
    /// and carries on using it there.
    public func moveLibrary(into folder: URL) throws {
        let destination = folder.appending(path: rootURL.lastPathComponent, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path(percentEncoded: false)])
        }
        try FileManager.default.moveItem(at: rootURL, to: destination)
        useLibrary(at: destination)
    }

    public func game(withID id: UUID) -> Gamebox? {
        games.first { $0.id == id }
    }

    private func ensureExists() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: gamesURL, withIntermediateDirectories: true)
        moveLooseGamesIntoGamesFolder()
        let marker = rootURL.appending(path: Self.markerFileName)
        if !fileManager.fileExists(atPath: marker.path(percentEncoded: false)) {
            try JSONEncoder().encode(Marker()).write(to: marker, options: .atomic)
        }
    }

    /// Earlier versions kept gameboxes at the top of the library; move them
    /// into Games.
    private func moveLooseGamesIntoGamesFolder() {
        let fileManager = FileManager.default
        let loose = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles])) ?? []
        for item in loose where ["dosgame", "boxer"].contains(item.pathExtension.lowercased()) {
            let destination = gamesURL.appending(path: item.lastPathComponent)
            if !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try? fileManager.moveItem(at: item, to: destination)
            }
        }
    }

    // MARK: Adding games

    /// A game already in the library that `added` is a copy of: the same
    /// game converted again, or one with the same title.
    private func existingGame(like added: Gamebox) -> Gamebox? {
        let others = games.filter { $0.url.standardizedFileURL != added.url.standardizedFileURL }
        return others.first { $0.id == added.id }
            ?? others.first { $0.title.localizedCaseInsensitiveCompare(added.title) == .orderedSame }
    }

    /// Settles a duplicate: replace the game already there (the new copy
    /// takes its place in collections), keep both, or skip the new one.
    public func resolve(_ duplicate: DuplicateImport, _ choice: DuplicateChoice) {
        duplicates.removeAll { $0.id == duplicate.id }
        let fileManager = FileManager.default
        switch choice {
        case .skip:
            try? fileManager.trashItem(at: duplicate.added.url, resultingItemURL: nil)
        case .replace:
            var added = duplicate.added
            added.info.id = duplicate.existing.id
            added.info.isFavorite = duplicate.existing.info.isFavorite
            try? added.save()
            if (try? fileManager.trashItem(at: duplicate.existing.url, resultingItemURL: nil)) != nil,
               duplicate.existing.url.pathExtension == added.url.pathExtension {
                try? fileManager.moveItem(at: added.url, to: duplicate.existing.url)
            }
        case .keepBoth:
            if duplicate.added.id == duplicate.existing.id {
                var added = duplicate.added
                added.info.id = UUID()
                try? added.save()
            }
        }
        reload()
    }

    /// Games added before DOS Boxer knew about BASIC programs, still set to
    /// start the bare interpreter: give them their programs (saved).
    private static func withBASICPrograms(_ games: [Gamebox]) -> [Gamebox] {
        games.map { game in
            guard !game.isReadOnly, !game.info.launchers.contains(where: { $0.commands != nil }),
                  let drive = game.info.drives.first(where: { $0.kind == .hardDisk }) else { return game }
            let launchers = LauncherFinder.withBASICPrograms(game.info.launchers, root: game.url.appending(path: drive.path),
                                                             gameName: game.name)
            guard launchers.count != game.info.launchers.count else { return game }
            var updated = game
            updated.info.launchers = launchers
            try? updated.save()
            return updated
        }
    }

    /// Two games can't share an ID (the grid would show one blank and
    /// select both): the one added first keeps it, later copies get new
    /// ones, saved where possible.
    private static func withUniqueIDs(_ games: [Gamebox]) -> [Gamebox] {
        var seen = Set<Gamebox.ID>()
        var renumbered: [URL: Gamebox] = [:]
        let oldestFirst = games.sorted { ($0.addedDate ?? .distantPast) < ($1.addedDate ?? .distantPast) }
        for game in oldestFirst where !seen.insert(game.id).inserted {
            var fixed = game
            fixed.info.id = UUID()
            if !fixed.isReadOnly { try? fixed.save() }
            seen.insert(fixed.id)
            renumbered[game.url] = fixed
        }
        return games.map { renumbered[$0.url] ?? $0 }
    }

    /// Makes a gamebox in `library` (a folder of gameboxes) from a game folder, ZIP file or gamebox,
    /// without a `GameLibrary` (for tools like the compatibility lab).
    nonisolated public static func importGame(from source: URL, into library: URL) throws -> URL {
        try GameImporter.makeGamebox(from: source, inLibrary: library)
    }

    /// Adds games from dropped or chosen items: game folders, ZIP archives,
    /// or existing gameboxes. Each becomes a `.dosgame` in the library; the
    /// originals are copied, never moved or changed.
    public func add(_ urls: [URL]) {
        for url in urls.flatMap(GameImporter.gamesInCollection) {
            let pending = PendingImport(name: url.deletingPathExtension().lastPathComponent)
            pendingImports.append(pending)
            importQueue.append((url, pending))
        }
        startImports()
    }

    /// Games waiting to be imported, in the order they were added.
    @ObservationIgnored private var importQueue: [(url: URL, pending: PendingImport)] = []
    @ObservationIgnored private var importsRunning = 0
    /// Imports copy and unpack whole games: two at a time keeps the disk
    /// busy without swamping it (or the app) when 100 are dropped at once.
    private static let simultaneousImports = 2

    private func startImports() {
        while importsRunning < Self.simultaneousImports, !importQueue.isEmpty {
            let (url, pending) = importQueue.removeFirst()
            importsRunning += 1
            let games = gamesURL
            Task.detached(priority: .userInitiated) {
                let result = Result { try GameImporter.makeGamebox(from: url, inLibrary: games) }
                await MainActor.run {
                    self.importsRunning -= 1
                    self.pendingImports.removeAll { $0.id == pending.id }
                    switch result {
                    case .failure(let error):
                        self.lastError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
                    case .success(let added):
                        if let added = try? Gamebox.open(added), let existing = self.existingGame(like: added) {
                            self.duplicates.append(DuplicateImport(added: added, existing: existing))
                        }
                    }
                    self.reload()
                    self.startImports()
                }
            }
        }
    }
}
