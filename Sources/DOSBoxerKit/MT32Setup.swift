import Foundation

/// Roland MT-32 music: many late-80s and early-90s games sound their best
/// on it. The emulator needs copies of the MT-32's ROM chips, which people
/// supply themselves (they're copyrighted). DOS Boxer keeps them in one
/// folder and points every game at it.
public enum MT32Setup {
    public enum Status: Equatable, Sendable {
        case notInstalled
        /// Some ROMs, but not a matching control + sound (PCM) pair.
        case incomplete
        case ready(model: String)
    }

    public static var romsFolder: URL {
        folderOverride ?? URL.applicationSupportDirectory.appending(path: "DOS Boxer/MT-32 ROMs",
                                                                    directoryHint: .isDirectory)
    }

    /// Lets tests use a scratch folder.
    nonisolated(unsafe) static var folderOverride: URL?

    // ROM sizes: control ROMs are 64 KB (MT-32) or 64/128 KB; sound ROMs
    // 512 KB (MT-32) or 1 MB (CM-32L / LAPC-I)
    private static let controlSizes: Set<Int> = [65_536, 131_072]
    private static let mt32PCMSize = 524_288
    private static let cm32lPCMSize = 1_048_576

    public static func status() -> Status {
        let sizes = romFiles().compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        let hasControl = sizes.contains(where: controlSizes.contains)
        let hasMT32Sound = sizes.contains(mt32PCMSize)
        let hasCM32LSound = sizes.contains(cm32lPCMSize)
        if hasControl && (hasMT32Sound || hasCM32LSound) {
            return .ready(model: hasCM32LSound && !hasMT32Sound ? "CM-32L" : "MT-32")
        }
        return sizes.isEmpty ? .notInstalled : .incomplete
    }

    /// Copies ROM files from `urls` (files, or folders containing them).
    /// Returns how many were added; files that aren't MT-32 ROMs are skipped.
    @discardableResult
    public static func install(from urls: [URL]) throws -> Int {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: romsFolder, withIntermediateDirectories: true)
        var added = 0
        for url in urls.flatMap(candidates) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard controlSizes.contains(size) || size == mt32PCMSize || size == cm32lPCMSize else { continue }
            let destination = romsFolder.appending(path: url.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
            added += 1
        }
        return added
    }

    public static func removeAll() throws {
        if FileManager.default.fileExists(atPath: romsFolder.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: romsFolder)
        }
    }

    /// dosbox settings pointing the MT-32 emulator at the ROMs, if installed.
    static func sessionArguments() -> [String] {
        guard case .ready = status() else { return [] }
        return ["--set", "mt32 romdir=\(romsFolder.path(percentEncoded: false))"]
    }

    private static func romFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: romsFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { ["rom", "bin"].contains($0.pathExtension.lowercased()) }
    }

    /// The ROM-looking files at `url` (itself, or inside it if a folder).
    private static func candidates(_ url: URL) -> [URL] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isFolder) else {
            return []
        }
        guard isFolder.boolValue else { return [url] }
        return ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { ["rom", "bin"].contains($0.pathExtension.lowercased()) }
    }
}
