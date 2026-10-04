import AppKit
import Foundation

/// Turns a game folder, ZIP archive or existing gamebox into a `.dosgame` in
/// the library. Runs off the main thread; copying can take a while.
enum GameImporter {
    enum ImportError: LocalizedError {
        case unsupported
        case emptyArchive

        var errorDescription: String? {
            switch self {
            case .unsupported: "DOS Boxer can add game folders, ZIP files and gameboxes."
            case .emptyArchive: "The ZIP file doesn't contain any files."
            }
        }
    }

    static func makeGamebox(from source: URL, inLibrary library: URL) throws -> URL {
        let fileManager = FileManager.default
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isFolder) else {
            throw CocoaError(.fileNoSuchFile)
        }

        switch source.pathExtension.lowercased() {
        case "dosgame":
            // Already a gamebox: just copy it in
            let destination = uniqueURL(named: source.deletingPathExtension().lastPathComponent, in: library)
            try fileManager.copyItem(at: source, to: destination)
            return destination
        case "boxer":
            return try convertBoxerGamebox(source, library: library)
        case "zip", "exo":
            let unpacked = try unzip(source)
            defer { try? fileManager.removeItem(at: unpacked) }
            return try makeGamebox(fromFolder: gameRoot(in: unpacked),
                                   name: displayName(for: source), library: library)
        default:
            guard isFolder.boolValue else { throw ImportError.unsupported }
            return try makeGamebox(fromFolder: source, name: displayName(for: source), library: library)
        }
    }

    /// Builds a new gamebox around a copy of `folder` as drive C.
    private static func makeGamebox(fromFolder folder: URL, name: String, library: URL) throws -> URL {
        let fileManager = FileManager.default
        let destination = uniqueURL(named: name, in: library)
        let driveC = destination.appending(path: "\(Gamebox.drivesFolder)/C", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: driveC.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: folder, to: driveC)

        // Box art that came with the game becomes the cover
        if let cover = CoverArtFinder.cover(in: driveC) {
            let coverURL = destination.appending(path: "\(Gamebox.coverBaseName).\(cover.pathExtension.lowercased())")
            try? fileManager.copyItem(at: cover, to: coverURL)
        }

        var info = Gamebox.Info(name: name)
        info.dateAdded = Date()
        info.drives = [Gamebox.Drive(letter: "C", kind: .hardDisk, path: "\(Gamebox.drivesFolder)/C")]
        // CD-based games ship their disc as an image; it becomes drive D
        let discs = DiscImageFinder.discs(in: driveC)
        if let first = discs.first {
            let relative = { (disc: URL) in
                ([Gamebox.drivesFolder, "C"] + LauncherFinder.relativeComponents(of: disc, under: driveC))
                    .joined(separator: "/")
            }
            info.drives.append(Gamebox.Drive(letter: "D", kind: .cdROM, path: relative(first),
                                             moreDiscs: discs.count > 1 ? discs.dropFirst().map(relative) : nil))
        }
        info.launchers = LauncherFinder.launchers(inDrive: "C", root: driveC, gameName: name)
        try Gamebox(url: destination, info: info).save()
        return destination
    }

    /// Copies an original Boxer gamebox into a new `.dosgame`: its drive
    /// folders, default program and box art (kept as Boxer's custom icon).
    private static func convertBoxerGamebox(_ source: URL, library: URL) throws -> URL {
        let fileManager = FileManager.default
        let boxer = try BoxerGamebox.open(source)
        let destination = uniqueURL(named: boxer.name, in: library)
        try fileManager.createDirectory(at: destination.appending(path: Gamebox.drivesFolder),
                                        withIntermediateDirectories: true)

        var info = boxer.info
        info.dateAdded = Date()
        info.drives = []
        for drive in boxer.info.drives {
            let target = "\(Gamebox.drivesFolder)/\(drive.letter)"
            let from = source.appending(path: drive.path, directoryHint: .isDirectory)
            let to = destination.appending(path: target, directoryHint: .isDirectory)
            if drive.path == "." {
                // Old-style gamebox: drive C is the package root, minus Boxer's own files
                try fileManager.createDirectory(at: to, withIntermediateDirectories: true)
                let skip: Set<String> = ["Game Info.plist", "Icon\r", "DOSBox Preferences.conf"]
                for item in try fileManager.contentsOfDirectory(atPath: from.path(percentEncoded: false))
                where !skip.contains(item) && !["harddisk", "cdrom", "floppy"].contains((item as NSString).pathExtension.lowercased()) {
                    try fileManager.copyItem(at: from.appending(path: item), to: to.appending(path: item))
                }
            } else {
                try fileManager.copyItem(at: from, to: to)
            }
            info.drives.append(Gamebox.Drive(letter: drive.letter, kind: drive.kind, path: target))
        }
        if info.launchers.isEmpty, let driveC = info.drives.first(where: { $0.letter == "C" }) {
            info.launchers = LauncherFinder.launchers(inDrive: "C", root: destination.appending(path: driveC.path),
                                                      gameName: info.name)
        }

        // Boxer kept box art as the package's custom Finder icon
        if let icon = try? source.resourceValues(forKeys: [.customIconKey]).customIcon,
           let tiff = icon.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: destination.appending(path: "\(Gamebox.coverBaseName).png"))
        }

        try Gamebox(url: destination, info: info).save()
        return destination
    }

    /// Unpacks a ZIP into a temporary folder.
    private static func unzip(_ archive: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "dosboxer-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path(percentEncoded: false), destination.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        return destination
    }

    /// Archives often wrap everything in one top-level folder (eXoDOS does);
    /// use that folder as the game's root.
    private static func gameRoot(in folder: URL) throws -> URL {
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            // Ignore archive clutter: macOS metadata, and the empty .exo
            // placeholder eXoDOS puts in every game archive
            .filter { $0.lastPathComponent != "__MACOSX" && $0.pathExtension.lowercased() != "exo" }
        guard !entries.isEmpty else { throw ImportError.emptyArchive }
        if entries.count == 1, (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return entries[0]
        }
        return folder
    }

    /// "Crystal Caves (1991).zip" → "Crystal Caves (1991)".
    private static func displayName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Untitled Game" : name
    }

    /// "Name.dosgame", or "Name 2.dosgame" if that's taken.
    private static func uniqueURL(named name: String, in library: URL) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var candidate = library.appending(path: "\(safe).dosgame", directoryHint: .isDirectory)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = library.appending(path: "\(safe) \(counter).dosgame", directoryHint: .isDirectory)
            counter += 1
        }
        return candidate
    }
}

/// Finds CD images among a game's files: cue sheets (which describe their
/// `.bin` data files) and ISO, CCD and MDF images. Several discs come back in
/// name order.
enum DiscImageFinder {
    static func discs(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var images: [URL] = []
        for case let file as URL in enumerator {
            if enumerator.level > 3 { enumerator.skipDescendants(); continue }
            if ["cue", "iso", "ccd", "mdf"].contains(file.pathExtension.lowercased()) {
                images.append(file)
            }
        }
        return images.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

/// Finds box art shipped alongside a game's files.
enum CoverArtFinder {
    static func cover(in folder: URL) -> URL? {
        let images = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
        let preferred = ["boxart", "cover", "box", "front", "folder"]
        return images.first { image in
            let name = image.deletingPathExtension().lastPathComponent.lowercased()
            return preferred.contains { name.contains($0) }
        } ?? (images.count == 1 ? images[0] : nil)
    }
}

/// Picks out the programs that start a game, and a sensible default, the way
/// a person would: obvious start scripts first, then a program named after
/// the game, skipping setup, install and readme tools.
enum LauncherFinder {
    private static let runnable = ["exe", "com", "bat"]
    private static let startScripts = ["run", "start", "play", "go", "game"]
    /// Name starts that mark a program as something other than the game:
    /// installers and setup tools, documentation, and support programs games
    /// rely on (DOS extenders, runtimes, unpackers). Found by running the
    /// compatibility lab over a few hundred games.
    private static let notTheGame = [
        // installing and configuring
        "setup", "install", "instal", "inst", "config", "cfg", "uninst", "setsound", "sound", "fix",
        "patch", "update", "upgrade", "register", "network",
        // documentation and printing
        "readme", "read", "help", "manual", "doc", "info", "order", "catalog", "vendor", "print", "intro",
        // support programs: DOS extenders, runtimes, memory managers, unpackers
        "cwsdpmi", "dos4gw", "dos32a", "pmode", "rtm", "dpmi", "brun", "qbrun", "himem", "emm", "mouse",
        "lharc", "lha", "pkunzip", "unzip", "arj", "decrunch", "unpack", "loadfix", "cdrom", "mscdex",
        "autoexec", "reset", "desinst", "loadpat",
    ]
    /// Words that mark a support program anywhere in its name (MPSFIX, KOFIX).
    private static let notTheGameAnywhere = ["fix", "patch", "setup", "install"]

    static func launchers(inDrive letter: String, root: URL, gameName: String) -> [Gamebox.Launcher] {
        let candidates = programs(in: root, depth: 4)
        guard !candidates.isEmpty else { return [] }

        let gameWords = Set(gameName.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        func score(_ program: URL) -> Int {
            let stem = program.deletingPathExtension().lastPathComponent.lowercased()
            let depth = relativeComponents(of: program, under: root).count - 1
            var score = 0
            if notTheGame.contains(where: { stem.hasPrefix($0) })
                || notTheGameAnywhere.contains(where: { stem.contains($0) }) { score -= 100 }
            if startScripts.contains(stem) && depth == 0 { score += 50 }
            // A batch file at the top of the game is almost always its start
            // script (eXoDOS archives put theirs there)
            if program.pathExtension.lowercased() == "bat" && depth == 0 { score += 30 }
            if gameWords.contains(where: { $0.count >= 3 && stem.hasPrefix(String($0.prefix(3))) }) { score += 20 }
            if program.pathExtension.lowercased() == "exe" { score += 5 }
            score -= depth * 10
            return score
        }

        // Best score first; equal scores in name order, so DUKE1 beats DUKE2
        let ranked = candidates.sorted {
            let (left, right) = (score($0), score($1))
            return left != right ? left > right
                : $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        return ranked.enumerated().map { index, program in
            let relative = relativeComponents(of: program, under: root).joined(separator: "\\")
            let stem = program.deletingPathExtension().lastPathComponent
            return Gamebox.Launcher(title: title(for: stem, gameName: gameName),
                                    dosPath: "\(letter):\\\(relative)",
                                    isDefault: index == 0 && score(program) > -100)
        }
    }

    /// Path components of `file` below `root`, comparing real paths so
    /// symlinks (like /var → /private/var) don't throw the count off.
    static func relativeComponents(of file: URL, under root: URL) -> [String] {
        let fileParts = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let rootParts = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard fileParts.starts(with: rootParts) else { return [file.lastPathComponent] }
        return Array(fileParts.dropFirst(rootParts.count))
    }

    private static func programs(in folder: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [] }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var found: [URL] = []
        for entry in entries {
            if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                found += programs(in: entry, depth: depth - 1)
            } else if runnable.contains(entry.pathExtension.lowercased()) {
                found.append(entry)
            }
        }
        return found
    }

    /// "SETUP" → "Setup"; a start script is labelled with the game's name.
    private static func title(for stem: String, gameName: String) -> String {
        startScripts.contains(stem.lowercased()) ? "Play \(gameName)" : stem.capitalized
    }
}
