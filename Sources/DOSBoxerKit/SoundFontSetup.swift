import Foundation

/// Sound Canvas (General MIDI) music: games scored for the Roland Sound
/// Canvas play through a SoundFont. DOS Boxer offers GeneralUser GS (by
/// S. Christian Collins; free to use and share, see Licenses/), downloaded
/// on request from DOS Boxer's own copy, or takes a SoundFont people add
/// themselves. Kept beside the MT-32 ROMs.
public enum SoundFontSetup {
    public static var folder: URL {
        folderOverride ?? URL.applicationSupportDirectory.appending(path: "DOS Boxer/SoundFonts",
                                                                    directoryHint: .isDirectory)
    }

    /// Lets tests use a scratch folder.
    nonisolated(unsafe) static var folderOverride: URL?

    /// DOS Boxer's copy of GeneralUser GS v2.0.3 (its author asks that apps
    /// don't download from his files directly).
    public static let downloadURL = URL(
        string: "https://github.com/cantcodewontcode/dos-boxer/releases/download/soundfont-1/GeneralUser-GS.sf2")!
    public static let downloadName = "GeneralUser-GS.sf2"
    public static let downloadSize = 32_319_396

    /// The SoundFont games use: one the player added, else GeneralUser GS.
    public static var installedFont: URL? {
        let fonts = soundFonts()
        return fonts.first { $0.lastPathComponent != downloadName } ?? fonts.first
    }

    public static var isReady: Bool { installedFont != nil }

    /// "GeneralUser GS", or a font's file name.
    public static var installedName: String? {
        guard let font = installedFont else { return nil }
        return font.lastPathComponent == downloadName ? "GeneralUser GS" : font.deletingPathExtension().lastPathComponent
    }

    static func soundFonts() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter(isSoundFont)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A SoundFont 2 file: a RIFF file of type "sfbk".
    public static func isSoundFont(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "sf2",
              let handle = try? FileHandle(forReadingFrom: url), let header = try? handle.read(upToCount: 12),
              header.count == 12 else { return false }
        return header.prefix(4) == Data("RIFF".utf8) && header.suffix(4) == Data("sfbk".utf8)
    }

    /// Copies SoundFonts from `urls`. Returns how many were added.
    @discardableResult
    public static func install(from urls: [URL]) throws -> Int {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var added = 0
        for url in urls where isSoundFont(url) {
            let destination = folder.appending(path: url.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
            added += 1
        }
        return added
    }

    public enum DownloadError: LocalizedError {
        case notASoundFont
        public var errorDescription: String? {
            "The download wasn't a complete SoundFont. Try again later."
        }
    }

    /// Downloads GeneralUser GS into the SoundFonts folder, reporting
    /// progress from 0 to 1.
    public static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = ProgressDelegate(progress: progress)
        let (file, _) = try await URLSession.shared.download(from: downloadURL, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: file) }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let renamed = file.deletingLastPathComponent().appending(path: downloadName)
        try? FileManager.default.removeItem(at: renamed)
        try FileManager.default.moveItem(at: file, to: renamed)
        defer { try? FileManager.default.removeItem(at: renamed) }
        guard size == downloadSize, isSoundFont(renamed) else { throw DownloadError.notASoundFont }
        try install(from: [renamed])
    }

    /// Removes every installed SoundFont.
    public static func removeAll() throws {
        for font in soundFonts() { try FileManager.default.removeItem(at: font) }
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
        let progress: @Sendable (Double) -> Void
        init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(SoundFontSetup.downloadSize)
            progress(min(1, Double(totalBytesWritten) / Double(total)))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}
