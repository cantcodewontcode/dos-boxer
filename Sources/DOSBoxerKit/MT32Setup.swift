import CryptoKit
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

    /// Copies ROM files from `urls` (files, or folders or ZIPs of them).
    /// Returns how many were added; files that aren't MT-32 ROMs, and copies
    /// of ROMs already installed, are skipped.
    @discardableResult
    public static func install(from urls: [URL]) throws -> Int {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: romsFolder, withIntermediateDirectories: true)
        var installed = Set(romFiles().compactMap(contentID))
        var added = 0
        for url in urls.flatMap({ roms(in: $0) ?? candidates($0) }) {
            guard hasROMSize(url), let id = contentID(url), installed.insert(id).inserted else { continue }
            var destination = romsFolder.appending(path: url.lastPathComponent)
            // Keep the ".rom" ending DOSBox looks for
            if !["rom", "bin"].contains(destination.pathExtension.lowercased()) {
                destination = destination.appendingPathExtension("rom")
            }
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
            added += 1
        }
        return added
    }

    /// The MT-32 ROMs in `url`, if that's what it is: a ROM file, or a
    /// folder or ZIP of ROMs (like the archive.org download, which holds
    /// several collections with their own file naming). Nil for anything
    /// else, such as a game. ZIPs are unpacked into a temporary folder, so
    /// the URLs are only good until the app quits.
    public static func roms(in url: URL) -> [URL]? {
        if url.pathExtension.lowercased() == "zip" {
            // ROM collections are small and hold no programs; look at the
            // ZIP's list of files before unpacking anything (a game ZIP can
            // be gigabytes)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            guard size <= 64_000_000, let names = zipEntryNames(url),
                  !names.contains(where: { ["exe", "com", "bat"].contains(($0 as NSString).pathExtension.lowercased()) })
            else { return nil }
            let folder = FileManager.default.temporaryDirectory
                .appending(path: "dosboxer-roms-\(UUID().uuidString)", directoryHint: .isDirectory)
            let ditto = Process()
            ditto.executableURL = URL(filePath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", url.path(percentEncoded: false), folder.path(percentEncoded: false)]
            guard (try? ditto.run()) != nil else { return nil }
            ditto.waitUntilExit()
            return roms(in: folder)
        }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isFolder) else {
            return nil
        }
        if !isFolder.boolValue {
            return isROM(url) ? [url] : nil
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles]) else { return nil }
        var found: [URL] = []
        for case let file as URL in enumerator
        where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            if file.path(percentEncoded: false).contains("__MACOSX") { continue }
            // Programs mean this is a game, not a ROM collection
            if ["exe", "com", "bat"].contains(file.pathExtension.lowercased()) { return nil }
            if hasROMSize(file) { found.append(file) }
        }
        // Prefer ".rom" names when the same ROM appears twice
        found.sort { ($0.pathExtension.lowercased() == "rom" ? 0 : 1) < ($1.pathExtension.lowercased() == "rom" ? 0 : 1) }
        var seen = Set<String>()
        found = found.filter { contentID($0).map { seen.insert($0).inserted } ?? false }
        return found.isEmpty ? nil : found
    }

    /// The sizes ROMs come in. (Collections also hold half-chip dumps of
    /// other sizes, which DOSBox can't use.)
    /// The file names inside a ZIP, read from its directory (no unpacking).
    private static func zipEntryNames(_ zip: URL) -> [String]? {
        let zipinfo = Process()
        zipinfo.executableURL = URL(filePath: "/usr/bin/zipinfo")
        zipinfo.arguments = ["-1", zip.path(percentEncoded: false)]
        let output = Pipe()
        zipinfo.standardOutput = output
        zipinfo.standardError = FileHandle.nullDevice
        guard (try? zipinfo.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        zipinfo.waitUntilExit()
        guard zipinfo.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private static func hasROMSize(_ url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return controlSizes.contains(size) || size == mt32PCMSize || size == cm32lPCMSize
    }

    private static func contentID(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// What's installed, in words: "MT-32 and CM-32L, 13 ROMs".
    public static func summary() -> String? {
        let files = romFiles()
        guard !files.isEmpty else { return nil }
        let sizes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        var models: [String] = []
        if sizes.contains(mt32PCMSize) { models.append("MT-32") }
        if sizes.contains(cm32lPCMSize) { models.append("CM-32L") }
        let count = files.count == 1 ? "1 ROM" : "\(files.count) ROMs"
        return models.isEmpty ? count : "\(models.joined(separator: " and ")), \(count)"
    }

    private static func isROM(_ url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ["rom", "bin"].contains(url.pathExtension.lowercased())
            && (controlSizes.contains(size) || size == mt32PCMSize || size == cm32lPCMSize)
    }

    /// The installed ROM files, by name.
    public static func installedROMs() -> [String] {
        romFiles().map(\.lastPathComponent).sorted()
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
