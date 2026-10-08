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
            let root = try gameRoot(in: unpacked)
            return try makeGamebox(fromFolder: root, name: displayName(for: source), library: library,
                                   shortName: root == unpacked ? nil : root.lastPathComponent)
        default:
            guard isFolder.boolValue else { throw ImportError.unsupported }
            return try makeGamebox(fromFolder: source, name: displayName(for: source), library: library,
                                   shortName: source.lastPathComponent)
        }
    }

    /// Builds a new gamebox around a copy of `folder` as drive C.
    private static func makeGamebox(fromFolder folder: URL, name: String, library: URL,
                                    shortName: String? = nil) throws -> URL {
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
        info.shortName = shortName
        // Collections put a game's menu script at the top of drive C; when
        // the game's files sit one folder down, C starts there (Day of the
        // Tentacle's script runs C:\DOTT.CD\TENTACLE.EXE)
        let menuFolder = LauncherFinder.menuFolder(in: driveC)
        info.drives = [Gamebox.Drive(letter: "C", kind: .hardDisk,
                                     path: "\(Gamebox.drivesFolder)/C" + (menuFolder.map { "/" + $0.lastPathComponent } ?? ""))]
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
        info.launchers = LauncherFinder.launchers(inDrive: "C", root: menuFolder ?? driveC, gameName: name)
        // Programs only on the CD: start from there
        if info.launchers.isEmpty, let cd = discs.first {
            info.launchers = LauncherFinder.launchersOnCD(cd, inDrive: "D", gameName: name)
        }
        info.launchers = LauncherFinder.expandingMenus(info.launchers, root: menuFolder ?? driveC)
        info.menuVersion = Gamebox.Info.menuVersion
        info.chooseBestSound(year: Gamebox.year(fromName: name), hasMT32: MT32Setup.isReady)
        var gamebox = Gamebox(url: destination, info: info)
        _ = ShippedGameSettings.apply(to: &gamebox)  // speeds and start programs found by playing
        try gamebox.save()
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

        var gamebox = Gamebox(url: destination, info: info)
        _ = ShippedGameSettings.apply(to: &gamebox)  // speeds and start programs found by playing
        try gamebox.save()
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
        let name = GameNames.articleFirst(url.deletingPathExtension().lastPathComponent)
        return name.isEmpty ? "Untitled Game" : name
    }

    /// "Name.dosgame", or "Name 2.dosgame" if that's taken.
    private static func uniqueURL(named name: String, in library: URL) -> URL {
        let safe = GameNames.fileName(name)
        var candidate = library.appending(path: "\(safe).dosgame", directoryHint: .isDirectory)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = library.appending(path: "\(safe) \(counter).dosgame", directoryHint: .isDirectory)
            counter += 1
        }
        return candidate
    }
}

extension GameImporter {
    /// What to import for a dropped item. A folder holding games (ZIPs or
    /// gameboxes) but no programs of its own, like a folder of downloads, is
    /// a collection: each game in it, and in folders like it inside, is
    /// imported separately. Anything else is one game.
    static func gamesInCollection(_ url: URL) -> [URL] {
        let fileManager = FileManager.default
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isFolder),
              isFolder.boolValue, !["dosgame", "boxer"].contains(url.pathExtension.lowercased()),
              let entries = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                 options: [.skipsHiddenFiles])
        else { return [url] }

        let isSubfolder = { (entry: URL) in
            !["dosgame", "boxer"].contains(entry.pathExtension.lowercased())
                && (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        let games = entries.filter { ["zip", "dosgame", "boxer"].contains($0.pathExtension.lowercased()) }
        let subfolders = entries.filter(isSubfolder)
        // Any other file (a program, game data) means this is a game itself
        let notes = ["txt", "md", "nfo", "diz", "pdf", "url", "rtf"]
        let hasPrograms = entries.contains { entry in
            !isSubfolder(entry) && !games.contains(entry) && !notes.contains(entry.pathExtension.lowercased())
        }
        // Folders inside that are collections themselves (e.g. one per year)
        let nested = subfolders.flatMap { folder in
            let inside = gamesInCollection(folder)
            return inside == [folder] ? [] : inside
        }
        guard !hasPrograms, !games.isEmpty || !nested.isEmpty else { return [url] }
        return games.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            + nested
    }
}

/// Finds CD images among a game's files: cue sheets (which describe their
/// `.bin` data files) and ISO, CCD and MDF images. Several discs come back in
/// name order.
enum DiscImageFinder {
    /// Best first: a disc often comes as several files ("GAME.ccd" with a
    /// "GAME.cue" for the same image), and DOSBox reads cue sheets best.
    private static let preference = ["cue", "iso", "mdf", "ccd"]

    static func discs(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var images: [URL] = []
        for case let file as URL in enumerator {
            if enumerator.level > 3 { enumerator.skipDescendants(); continue }
            if preference.contains(file.pathExtension.lowercased()) {
                images.append(file)
            }
        }
        // One file per disc
        let discs = Dictionary(grouping: images) { $0.deletingPathExtension().path.lowercased() }
            .values.compactMap { files in
                files.min { preference.firstIndex(of: $0.pathExtension.lowercased())!
                    < preference.firstIndex(of: $1.pathExtension.lowercased())! }
            }
        return discs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
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
    private static let startScripts = ["run", "start", "play", "go"]
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

    static func launchers(inDrive letter: String, root: URL, gameName: String,
                          candidates: [URL]? = nil) -> [Gamebox.Launcher] {
        let candidates = candidates ?? programs(in: root, depth: 4)
        guard !candidates.isEmpty else { return [] }

        let words = gameName.replacingOccurrences(of: #"\s*\(\d{3}[\dx]\)\s*$"#, with: "", options: .regularExpression)
            .lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let gameWords = Set(words)
        // "JD" for Judge Dredd
        let initials = String(words.filter { !["the", "of", "and", "a"].contains($0) }.compactMap(\.first))
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
            // Named after the game outright ("COVERT" for Covert Action)
            if stem.count >= 4, gameWords.contains(where: { $0.hasPrefix(stem) }) {
                score += 25
            }
            if initials.count >= 2, stem == initials { score += 25 }
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
        let launchers = ranked.enumerated().map { index, program in
            let relative = relativeComponents(of: program, under: root).joined(separator: "\\")
            let stem = program.deletingPathExtension().lastPathComponent
            return Gamebox.Launcher(title: title(for: stem, gameName: gameName),
                                    dosPath: "\(letter):\\\(relative)",
                                    isDefault: index == 0 && score(program) > -100)
        }
        return withBASICPrograms(launchers, root: root, gameName: gameName)
    }

    /// The folder a game's drive C should start at, when its batch files
    /// say so: the top of its files has no programs of its own and holds
    /// just one folder, with the menu script (run.bat), and the batch files
    /// there use fixed paths that only exist inside it (Day of the
    /// Tentacle's script runs C:\DOTT.CD\TENTACLE.EXE). Nil otherwise: most
    /// games expect C at the top (collections mount them that way).
    static func menuFolder(in root: URL) -> URL? {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let folders = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let hasPrograms = entries.contains { runnable.contains($0.pathExtension.lowercased()) }
        guard folders.count == 1, !hasPrograms, let folder = folders.first,
              let inside = try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)),
              inside.contains(where: { $0.lowercased() == "run.bat" }) else { return nil }

        // Evidence: a batch file naming C:\<something> that's in the folder
        // but not at the top
        let insideNames = Set(inside.map { $0.lowercased() })
        let topNames = Set(entries.map { $0.lastPathComponent.lowercased() })
        let pathPattern = /(?i)c:\\([a-z0-9_.~-]+)/
        let batchFiles = (fileManager.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension.lowercased() == "bat" && LauncherFinder.relativeComponents(of: $0, under: folder).count <= 2 }
        for file in batchFiles {
            guard let text = try? String(contentsOf: file, encoding: .isoLatin1) else { continue }
            for match in text.matches(of: pathPattern) {
                let name = String(match.1).lowercased()
                if insideNames.contains(name) && !topNames.contains(name) { return folder }
            }
        }
        return nil
    }

    /// For a game with no programs of its own on drive C (The Dig): its
    /// programs on the CD in drive D, the game's first. A program at the top
    /// of the disc that's also in a folder is usually its installer, so the
    /// folder's copy ranks first.
    static func launchersOnCD(_ image: URL, inDrive letter: String, gameName: String) -> [Gamebox.Launcher] {
        guard let files = CDImage.files(in: image) else { return [] }
        let programs = files.filter { runnable.contains(($0 as NSString).pathExtension.lowercased()) }
        let inFolders = Set(programs.filter { $0.contains("/") }.map { ($0 as NSString).lastPathComponent.lowercased() })
        // Stand-in locations so the usual ranking can weigh names and depth
        let root = URL(filePath: "/DOSBoxerCD", directoryHint: .isDirectory)
        let candidates = programs
            .filter { $0.contains("/") || !inFolders.contains($0.lowercased()) }
            .map { root.appending(path: $0) }
        return launchers(inDrive: letter, root: root, gameName: gameName, candidates: candidates)
    }

    // MARK: BASIC games

    /// BASIC interpreters games ship with, and how each runs a program.
    /// The command that runs a program, before its file name.
    private static let interpreters: [String: String] = [
        "GWBASIC.EXE": "GWBASIC", "BASICA.COM": "BASICA", "BASICA.EXE": "BASICA",
        "BASIC.COM": "BASIC", "QBASIC.EXE": "QBASIC /RUN",
    ]

    /// When the game starts with a BASIC interpreter, adds a way to start
    /// each BASIC program beside it (run through the interpreter), the one
    /// named after the game first and as the default. Programs are
    /// recognized by their contents, whatever they're called (Draw Poker's
    /// is POKER.COL).
    static func withBASICPrograms(_ launchers: [Gamebox.Launcher], root: URL, gameName: String) -> [Gamebox.Launcher] {
        guard let interpreter = launchers.first(where: \.isDefault),
              interpreter.commands == nil,
              let fileName = interpreter.dosPath.split(separator: "\\").last.map({ String($0).uppercased() }),
              let command = interpreters[fileName] else { return launchers }
        let parts = interpreter.dosPath.split(separator: "\\").dropFirst().dropLast().map(String.init)
        let folder = root.appending(path: parts.joined(separator: "/"), directoryHint: .isDirectory)
        let programs = basicPrograms(in: folder)
        guard !programs.isEmpty else { return launchers }

        let words = gameName.replacingOccurrences(of: #"\s*\(\d{3}[\dx]\)\s*$"#, with: "", options: .regularExpression)
            .lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let initials = String(words.filter { !["the", "of", "and", "a", "to"].contains($0) }.compactMap(\.first))
        let fullInitials = String(words.compactMap(\.first))
        func score(_ program: URL) -> Int {
            let stem = program.deletingPathExtension().lastPathComponent.lowercased()
            var score = 0
            if stem == initials || stem == fullInitials { score += 30 }
            if words.contains(where: { $0.count >= 3 && (stem.hasPrefix($0) || $0.hasPrefix(stem) && stem.count >= 3) }) {
                score += 20
            }
            if ["menu", "start", "run", "main", "play"].contains(stem) { score += 15 }
            return score
        }
        let ranked = programs.sorted { score($0) != score($1) ? score($0) > score($1)
            : $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let basic = ranked.enumerated().map { index, program in
            Gamebox.Launcher(title: program.lastPathComponent.uppercased(), dosPath: interpreter.dosPath,
                             isDefault: index == 0, commands: ["\(command) \(program.lastPathComponent.uppercased())"])
        }
        return basic + launchers.map { launcher in
            var launcher = launcher
            launcher.isDefault = false
            return launcher
        }
    }

    /// BASIC programs in `folder`: GW-BASIC's saved format (first byte FF,
    /// or FE when protected), or a text .BAS file.
    static func basicPrograms(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey]))
            ?? []
        return files.filter { file in
            let ext = file.pathExtension.lowercased()
            guard !["exe", "com", "bat", "sys", "ovl", "dll", "zip", "txt", "doc"].contains(ext),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let handle = try? FileHandle(forReadingFrom: file) else { return false }
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 2)) ?? Data()
            if let first = head.first, first == 0xFF || first == 0xFE, head.count == 2 { return true }
            return ext == "bas"
        }
    }

    /// If the default launcher is a menu script (eXoDOS's "Press 1 for…"),
    /// puts each menu option first as its own launcher, the first one as the
    /// default, and keeps the script itself as "Menu".
    static func expandingMenus(_ launchers: [Gamebox.Launcher], root: URL) -> [Gamebox.Launcher] {
        guard !launchers.contains(where: { $0.commands != nil }) else { return launchers }
        // The default is a menu script: its options come first, the first
        // one the default
        if let script = launchers.first(where: \.isDefault), let options = menuOptions(of: script, root: root) {
            let fromMenu = options.enumerated().map { index, option in
                Gamebox.Launcher(title: option.title, dosPath: script.dosPath, isDefault: index == 0,
                                 commands: option.commands, disc: option.disc)
            }
            let rest = launchers.map { launcher in
                var launcher = launcher
                if launcher.id == script.id { launcher.title = "Menu" }
                launcher.isDefault = false
                return launcher
            }
            return fromMenu + rest
        }
        // Otherwise a start script elsewhere with a menu (Blackthorne's
        // BTHORNE\RUN.BAT): its options are added after the default, which
        // stays as it is
        for script in launchers where !script.isDefault && isStartScript(script) {
            guard let options = menuOptions(of: script, root: root) else { continue }
            let fromMenu = options.map { option in
                Gamebox.Launcher(title: option.title, dosPath: script.dosPath, commands: option.commands, disc: option.disc)
            }
            var result = launchers
            if let index = result.firstIndex(where: { $0.id == script.id }) { result[index].title = "Menu" }
            let afterDefault = (result.firstIndex(where: \.isDefault) ?? -1) + 1
            result.insert(contentsOf: fromMenu, at: afterDefault)
            return result
        }
        return launchers
    }

    private static func isStartScript(_ launcher: Gamebox.Launcher) -> Bool {
        let file = launcher.dosPath.split(separator: "\\").last.map { String($0).lowercased() } ?? ""
        return file.hasSuffix(".bat") && startScripts.contains(String(file.dropLast(4)))
    }

    /// The options of a "Press 1 for…" menu script, or nil if it isn't one.
    private static func menuOptions(of script: Gamebox.Launcher, root: URL) -> [BatchMenuReader.Option]? {
        guard script.dosPath.lowercased().hasSuffix(".bat") else { return nil }
        let parts = script.dosPath.split(separator: "\\").dropFirst().map(String.init)
        let scriptFolder = Array(parts.dropLast())
        guard let text = try? String(contentsOf: root.appending(path: parts.joined(separator: "/")), encoding: .isoLatin1)
        else { return nil }
        let options = BatchMenuReader.options(in: text) { folder, name in
            let directory = root.appending(path: (scriptFolder + folder).joined(separator: "/"), directoryHint: .isDirectory)
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
            return entries.contains { $0.lowercased() == "\(name.lowercased()).bat" }
        }
        return options.isEmpty ? nil : options
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
