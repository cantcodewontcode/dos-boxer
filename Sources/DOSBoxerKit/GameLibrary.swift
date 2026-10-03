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
    /// Set while games are being added, for progress UI.
    public private(set) var importsInProgress = 0
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

    public static var defaultLocation: URL {
        URL.homeDirectory.appending(path: "DOSBoxer", directoryHint: .isDirectory)
    }

    public init() {
        let saved = UserDefaults.standard.string(forKey: Self.locationKey)
        rootURL = saved.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Self.defaultLocation
        reload()
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
            let entries = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles])
            games = entries
                .filter { ["dosgame", "boxer"].contains($0.pathExtension.lowercased()) }
                .compactMap { try? Gamebox.open($0) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            lastError = nil
        } catch {
            lastError = "Couldn't read the library at \(rootURL.path(percentEncoded: false)): \(error.localizedDescription)"
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
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let marker = rootURL.appending(path: Self.markerFileName)
        if !fileManager.fileExists(atPath: marker.path(percentEncoded: false)) {
            try JSONEncoder().encode(Marker()).write(to: marker, options: .atomic)
        }
    }

    // MARK: Adding games

    /// Adds games from dropped or chosen items: game folders, ZIP archives,
    /// or existing gameboxes. Each becomes a `.dosgame` in the library; the
    /// originals are copied, never moved or changed.
    public func add(_ urls: [URL]) {
        for url in urls {
            importsInProgress += 1
            let root = rootURL
            Task.detached(priority: .userInitiated) {
                let result = Result { try GameImporter.makeGamebox(from: url, inLibrary: root) }
                await MainActor.run {
                    self.importsInProgress -= 1
                    if case .failure(let error) = result {
                        self.lastError = "Couldn't add \(url.lastPathComponent): \(error.localizedDescription)"
                    }
                    self.reload()
                }
            }
        }
    }
}
