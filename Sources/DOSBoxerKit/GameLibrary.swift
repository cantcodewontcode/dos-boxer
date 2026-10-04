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
    /// A game being copied into the library, shown as a placeholder card.
    public struct PendingImport: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
    }

    /// Games still being added, for progress UI.
    public private(set) var pendingImports: [PendingImport] = []
    public private(set) var lastError: String? {
        didSet { if let lastError { FileHandle.standardError.write(Data("DOS Boxer library: \(lastError)\n".utf8)) } }
    }

    /// What's stored in `Library.json`.
    struct Marker: Codable {
        var formatVersion = 1
        var id = UUID()
    }

    static let markerFileName = "Library.json"
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

    public init() {
        let saved = UserDefaults.standard.string(forKey: Self.locationKey)
        rootURL = saved.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Self.defaultLocation
        reload()
        // Keep "Recently Played" and "Most Played" current
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
            games = entries
                .filter { ["dosgame", "boxer"].contains($0.pathExtension.lowercased()) }
                .compactMap { try? Gamebox.open($0) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            lastError = nil
            fetchMissingCovers()
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

    /// Looks online for `game`'s box art again, replacing nothing it has.
    public func findCoverArt(for game: Gamebox) {
        Task {
            if await CoverArtFetcher.shared.fetchCover(for: game, evenIfRemoved: true) {
                reload()
            } else {
                lastError = "No box art was found for \(game.name). You can drop an image onto the game to use it as the cover."
            }
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

    /// Moves `game` (with its saved games) to the Trash.
    public func delete(_ game: Gamebox) {
        do {
            try FileManager.default.trashItem(at: game.url, resultingItemURL: nil)
            reload()
        } catch {
            lastError = "Couldn't move \(game.name) to the Trash: \(error.localizedDescription)"
        }
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

    /// Makes a gamebox in `library` (a folder of gameboxes) from a game folder, ZIP file or gamebox,
    /// without a `GameLibrary` (for tools like the compatibility lab).
    nonisolated public static func importGame(from source: URL, into library: URL) throws -> URL {
        try GameImporter.makeGamebox(from: source, inLibrary: library)
    }

    /// Adds games from dropped or chosen items: game folders, ZIP archives,
    /// or existing gameboxes. Each becomes a `.dosgame` in the library; the
    /// originals are copied, never moved or changed.
    public func add(_ urls: [URL]) {
        for url in urls {
            let pending = PendingImport(name: url.deletingPathExtension().lastPathComponent)
            pendingImports.append(pending)
            let games = gamesURL
            Task.detached(priority: .userInitiated) {
                let result = Result { try GameImporter.makeGamebox(from: url, inLibrary: games) }
                await MainActor.run {
                    self.pendingImports.removeAll { $0.id == pending.id }
                    if case .failure(let error) = result {
                        self.lastError = "Couldn't add \(url.lastPathComponent): \(error.localizedDescription)"
                    }
                    self.reload()
                }
            }
        }
    }
}
