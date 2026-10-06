import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A DOS Boxer gamebox: a package folder ending in `.dosgame`.
    public static let dosGame = UTType(exportedAs: "com.dosboxer.game", conformingTo: .package)
    /// An original Boxer gamebox (`.boxer`), which we can open and convert.
    public static let boxerGame = UTType(importedAs: "net.washboardabs.boxer-game-package", conformingTo: .package)
}

/// A game and everything it needs, kept together in one package:
///
///     Crystal Caves.dosgame/
///       Game.json        name, drives, launchers, settings
///       Drives/C/        the game's files (never written to while playing)
///       Saves/C/         everything the game writes: saves, configs, high scores
///       Cover.jpeg       box art (optional)
///
/// Games write into `Saves` through an overlay drive, so the original files
/// stay pristine and "revert to original" is just emptying `Saves`.
public struct Gamebox: Sendable, Identifiable {
    public var url: URL
    public var info: Info
    /// The box art file, looked up when the gamebox is opened. Stored (not
    /// computed from disk) so a new cover makes the value change and views
    /// showing it redraw.
    public private(set) var coverURL: URL?
    /// When the cover file last changed, so a replaced cover redraws too.
    public private(set) var coverDate: Date?
    /// How much the game has been played, across all Macs.
    public private(set) var stats = PlayStats()

    /// The look to draw this game with: its own, or the app-wide one.
    public var effectiveDisplayLook: DisplayLook {
        info.displayLook ?? .appDefault
    }

    /// DOSBox Staging's controller layout for this game, if it has one
    /// (about 200 games, named after their eXoDOS short names).
    public var controllerMapping: URL? {
        guard let shortName = info.shortName, let resources = Bundle.main.resourceURL else { return nil }
        let file = resources.appending(path: "mapperfiles/xbox/\(shortName.lowercased()).map")
        return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
    }

    /// Documents you've added to the game yourself (manuals, maps, notes).
    public var documentsURL: URL {
        url.appending(path: "Documents", directoryHint: .isDirectory)
    }

    /// Copies documents into the gamebox's Documents folder.
    public func addDocuments(_ files: [URL]) throws {
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        for file in files {
            let destination = documentsURL.appending(path: file.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: file, to: destination)
        }
    }

    /// Readmes, manuals and other documents: ones you added first, then
    /// ones that came with the game, most useful first (some games ask
    /// questions from the manual to start).
    public func documents() -> [URL] {
        let added = ((try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil,
                                                                    options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return added + bundledDocuments()
    }

    private func bundledDocuments() -> [URL] {
        guard let drive = info.drives.first(where: { $0.letter == "C" }) else { return [] }
        let root = url.appending(path: drive.path, directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        let documentTypes = ["pdf", "txt", "doc", "docx", "rtf", "htm", "html", "md", "nfo", "diz", "me", "1st"]
        let usefulWords = ["manual", "readme", "read", "guide", "help", "instruct", "story", "hint", "walk"]
        var found: [(url: URL, score: Int)] = []
        for case let file as URL in enumerator {
            if enumerator.level > 4 { enumerator.skipDescendants(); continue }
            let ext = file.pathExtension.lowercased()
            let stem = file.deletingPathExtension().lastPathComponent.lowercased()
            guard documentTypes.contains(ext) else { continue }
            var score = usefulWords.contains { stem.contains($0) } ? 10 : 0
            if ext == "pdf" { score += 5 }
            if ext == "diz" || ext == "nfo" { score -= 5 }
            found.append((file, score - enumerator.level))
        }
        return found.sorted {
            $0.score != $1.score ? $0.score > $1.score
                : $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }.prefix(20).map(\.url)
    }

    /// When the game joined the library (falling back to the package's
    /// creation date for games added before this was recorded).
    public var addedDate: Date? {
        info.dateAdded ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
    }

    /// The name without the trailing year, e.g. "Crystal Caves" (the grid
    /// leaves the year to the info panel).
    public var title: String {
        name.replacingOccurrences(of: #"\s*\(\d{3}[\dx]\)\s*$"#, with: "", options: .regularExpression)
    }

    /// The full name for a new title, keeping the year: "Crystal Caves II"
    /// becomes "Crystal Caves II (1991)" (sorting and the Years list use it).
    public func name(forTitle newTitle: String) -> String {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let alreadyHasYear = trimmed.range(of: #"\(\d{3}[\dx]\)\s*$"#, options: .regularExpression) != nil
        guard let year, !alreadyHasYear else { return trimmed }
        return "\(trimmed) (\(year))"
    }

    /// The release year: from the game's details, otherwise from the name,
    /// e.g. 1991 for "Crystal Caves (1991)".
    public var year: Int? {
        if let released = info.released, let year = Int(released.prefix(4)) { return year }
        return Self.year(fromName: name)
    }

    /// The year at the end of a name: 1991 for "Crystal Caves (1991)".
    static func year(fromName name: String) -> Int? {
        name.range(of: #"\((\d{4})\)\s*$"#, options: .regularExpression)
            .flatMap { Int(name[$0].dropFirst().prefix(4)) }
    }
    /// Where writes go when they can't live inside the package (original
    /// Boxer gameboxes, which we only read). Nil means `<package>/Saves`.
    var externalSavesURL: URL?

    public var id: UUID { info.id }
    public var name: String { info.name }

    /// What's stored in `Game.json`.
    public struct Info: Codable, Sendable {
        public var formatVersion = 1
        public var id = UUID()
        public var name: String
        public var drives: [Drive] = []
        public var launchers: [Launcher] = []
        /// dosbox settings as "section key" → value, e.g. "cpu cycles" → "max".
        public var settings: [String: String] = [:]
        /// Close the game when its program ends, instead of leaving people
        /// at a DOS prompt. Missing means yes.
        public var quitsWhenGameEnds: Bool?
        /// When the game was added to the library.
        public var dateAdded: Date?
        /// Who published and made the game. Filled in from the game details
        /// download (or Wikidata), and editable.
        public var publisher: String?
        public var developer: String?
        /// Kinds of game, from `GameGenres.all` (e.g. "Action", "Platform").
        public var genres: [String]?
        /// Older gameboxes kept genres as one line of free text; read through
        /// `genreList`, which maps it onto the known genres.
        public var genre: String?
        /// The game's entry in the LaunchBox Games Database, once matched.
        public var launchBoxID: Int?
        /// "1991-10-22", or just "1991".
        public var released: String?
        public var maxPlayers: Int?
        /// Players can play together (rather than only against each other).
        public var cooperative: Bool?
        /// ESRB age rating, e.g. "T - Teen". Nil when not rated.
        public var ageRating: String?
        /// Players' rating out of 5, and how many people rated it.
        public var communityRating: Double?
        public var communityRatingCount: Int?
        /// A description of the game.
        public var overview: String?
        /// What controller buttons do in this game, if changed.
        public var controls: GameControls?
        /// DOS Boxer has picked the best of the game's sound options (once).
        public var soundChosen: Bool?
        /// Which version of that choosing it was (newer rules choose again).
        public var soundChoiceVersion: Int?
        /// Which version of menu reading made the menu choices (newer
        /// readers read the menu again).
        public var menuVersion: Int?
        /// When the details were last looked up online.
        public var detailsCheckedAt: Date?
        /// The game's short folder name in the collection it came from (e.g.
        /// eXoDOS's "CKeen1"), used to find its controller mapping.
        public var shortName: String?
        /// Shown under Favorites in the library.
        public var isFavorite: Bool?
        /// This game's own display look; nil follows the app-wide setting.
        public var displayLook: DisplayLook?
        /// Set when someone removed the cover on purpose, so it isn't
        /// fetched again automatically.
        public var noCover: Bool?

        public var closesWhenGameEnds: Bool { quitsWhenGameEnds ?? true }

        /// Orders the game's menu choices best sound first and starts it with
        /// the best, once: MT-32 when its ROMs are installed (General MIDI
        /// leads for games from 1993 on), then Sound Blaster, AdLib, Gravis Ultrasound,
        /// Tandy, and PC Speaker last. Choices that aren't about sound (like
        /// network play) come after and aren't picked. Returns true if
        /// anything changed.
        @discardableResult
        public mutating func chooseBestSound(year: Int?, hasMT32: Bool) -> Bool {
            guard (soundChoiceVersion ?? 0) < Self.soundChoiceVersion else { return false }
            soundChoiceVersion = Self.soundChoiceVersion
            soundChosen = true
            let options = launchers.filter { $0.commands != nil }
            guard !options.isEmpty else { return true }
            func rank(_ launcher: Launcher) -> Int {
                let title = launcher.title.lowercased()
                let has = { (words: [String]) in words.contains { title.contains($0) } }
                // MT-32 only leads when its ROMs are installed and the game is
                // from its era; without ROMs it's never picked
                if has(["mt-32", "mt32"]) {
                    return hasMT32 ? (year.map((1987...1992).contains) == true ? 100 : 90) : 5
                }
                // Music recorded on the game's CD: the real thing
                if has(["cd audio", "cd music", "redbook"]) { return 110 }
                if has(["sound canvas", "general midi", "sc-55", "sc55", "roland sc"]) {
                    return (year ?? 0) >= 1993 ? 95 : 45
                }
                if has(["soundblaster", "sound blaster", "sb16", "sbpro", "sb pro"]) { return 80 }
                if has(["adlib", "ad lib"]) { return 70 }
                if has(["gravis", "ultrasound", "gus"]) { return 60 }
                if has(["tandy", "pcjr"]) { return 30 }
                if has(["pc speaker", "speaker", "internal"]) { return 20 }
                if has(["network", "multiplayer", "modem", "setup", "install", "config", "editor", "manual", "readme"]) {
                    return -10
                }
                return 10
            }
            // Best first, the menu's own order among equals
            let ranked = options.enumerated().sorted { a, b in
                rank(a.element) != rank(b.element) ? rank(a.element) > rank(b.element) : a.offset < b.offset
            }.map(\.element)
            let others = launchers.filter { $0.commands == nil }
            guard let best = ranked.first(where: { rank($0) >= 0 }) ?? ranked.first else { return true }
            launchers = (ranked + others).map { launcher in
                var launcher = launcher
                launcher.isDefault = launcher.id == best.id
                return launcher
            }
            return true
        }
        /// Bump to choose again for games already in libraries.
        static let soundChoiceVersion = 4
        /// Bump to read games' menus again (Blood's two-step menu).
        public static let menuVersion = 3

        /// The game's genres, including ones saved by older versions.
        public var genreList: [String] {
            if let genres { return genres }
            // Older free-form genres, mapped onto the known ones
            var list: [String] = []
            for part in (genre ?? "").components(separatedBy: ",") {
                if let known = GameGenres.closest(part.trimmingCharacters(in: .whitespaces)), !list.contains(known) {
                    list.append(known)
                }
            }
            return list
        }

        /// Replaces the genres (clearing the older one-line form).
        public mutating func setGenres(_ list: [String]) {
            genres = list.isEmpty ? nil : list
            genre = nil
        }
    }

    public struct Drive: Codable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable { case hardDisk, cdROM, floppy }
        /// "C", "D", …
        public var letter: String
        public var kind: Kind
        /// Path inside the gamebox: a folder ("Drives/C") or, for CD-ROMs, a
        /// disc image ("Drives/C/cd/game.cue").
        public var path: String
        /// Further disc images for multi-disc games (swapped in DOS with
        /// Ctrl+F4).
        public var moreDiscs: [String]?

        public init(letter: String, kind: Kind, path: String, moreDiscs: [String]? = nil) {
            self.letter = letter
            self.kind = kind
            self.path = path
            self.moreDiscs = moreDiscs
        }
    }

    /// How a game's programs are listed: its curated choices (from its menu,
    /// or BASIC programs) first, then everything else.
    public static func listed(_ launchers: [Launcher]) -> (choices: [Launcher], others: [Launcher]) {
        (launchers.filter { $0.commands != nil }, launchers.filter { $0.commands == nil })
    }

    /// A program people start the game with.
    public struct Launcher: Codable, Sendable, Hashable, Identifiable {
        public var id = UUID()
        public var title: String
        /// DOS path including the drive, e.g. `C:\CC1\CC1.EXE`.
        public var dosPath: String
        public var isDefault = false
        /// For an option read from a menu script: the commands to run instead
        /// of `dosPath`, from `dosPath`'s folder.
        public var commands: [String]?

        /// How the program is listed: its file name (e.g. KEEN1.EXE), or a
        /// menu option's title.
        public var displayName: String {
            commands != nil ? title : String(dosPath.split(separator: "\\").last ?? Substring(title))
        }
    }

    // MARK: Files

    static let infoFileName = "Game.json"
    static let drivesFolder = "Drives"
    static let savesFolder = "Saves"
    static let coverBaseName = "Cover"

    /// True when the package itself must not be written to (original Boxer
    /// gameboxes). Their saves live elsewhere.
    public var isReadOnly: Bool {
        externalSavesURL != nil || url.pathExtension.lowercased() != "dosgame"
    }

    public var savesURL: URL {
        externalSavesURL ?? url.appending(path: Self.savesFolder, directoryHint: .isDirectory)
    }

    public init(url: URL, info: Info) {
        self.url = url
        self.info = info
        self.coverURL = Self.findCover(in: url)
        self.coverDate = coverURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        self.stats = PlayStats.load(for: url)
    }

    private static func findCover(in url: URL) -> URL? {
        ["jpeg", "jpg", "png", "heic"]
            .map { url.appending(path: "\(coverBaseName).\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    public var defaultLauncher: Launcher? {
        info.launchers.first(where: \.isDefault) ?? info.launchers.first
    }

    /// Opens a gamebox: a `.dosgame` package, or an original Boxer `.boxer`
    /// package (read through an adapter; it isn't modified until saved).
    public static func open(_ url: URL) throws -> Gamebox {
        if url.pathExtension.lowercased() == "boxer" {
            return try BoxerGamebox.open(url)
        }
        let data = try Data(contentsOf: url.appending(path: infoFileName))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var info = try decoder.decode(Info.self, from: data)
        info.drives = info.drives.map(preferringCueSheets)
        return Gamebox(url: url, info: info)
    }

    /// Earlier imports could mount a CloneCD ".ccd" (which DOSBox can't
    /// read) and list the same disc's ".cue" as another disc; use the cue.
    private static func preferringCueSheets(_ drive: Drive) -> Drive {
        guard drive.kind == .cdROM else { return drive }
        let base = { (path: String) in (path as NSString).deletingPathExtension.lowercased() }
        let ext = { (path: String) in (path as NSString).pathExtension.lowercased() }
        var fixed = drive
        if ["ccd", "mdf"].contains(ext(drive.path)),
           let cue = drive.moreDiscs?.first(where: { ext($0) == "cue" && base($0) == base(drive.path) }) {
            fixed.path = cue
        }
        fixed.moreDiscs = drive.moreDiscs?.filter { base($0) != base(fixed.path) }
        if fixed.moreDiscs?.isEmpty == true { fixed.moreDiscs = nil }
        return fixed
    }

    /// Writes `Game.json`.
    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(info).write(to: url.appending(path: Self.infoFileName), options: .atomic)
    }

    /// Saves a screenshot as "<game> <date> <time>.png" in `folder`
    /// (normally the library's Screenshots folder). Returns its location.
    public func saveScreenshot(_ png: Data, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .dateTimeSeparator(.space).timeSeparator(.omitted))
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let file = folder.appending(path: "\(safeName) \(stamp).png")
        try png.write(to: file, options: .atomic)
        return file
    }

    /// Where screenshots go when there's no library.
    public static var defaultScreenshotsFolder: URL {
        URL.picturesDirectory.appending(path: "DOS Boxer", directoryHint: .isDirectory)
    }

    /// Discards everything the game has written (saves, settings it changed),
    /// returning it to how it was installed.
    public func revertToOriginal() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: savesURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: savesURL)
        }
    }

    // MARK: Session

    /// What a session should start with.
    public enum Start: Sendable, Hashable {
        /// The default launcher.
        case game
        case launcher(Launcher)
        /// A DOS prompt with the game's drives mounted.
        case prompt
    }

    /// dosbox arguments that mount the drives (with saves overlaid) and then
    /// run the game, a specific launcher, or just give a prompt.
    /// Settings games from a period usually need, before the game's own.
    /// DOSBox's 16 MB isn't enough for many mid-90s games, which quit at once.
    static func eraSettings(year: Int?) -> [String: String] {
        guard let year else { return [:] }
        // Games up to 1983 were written for the original IBM PC (4.77 MHz,
        // about 300 on DOSBox's scale); many run as fast as the machine
        // allows and are unplayable at DOSBox's usual speed
        if year <= 1983 { return ["cpu cpu_cycles": Self.originalPCSpeed] }
        // Games from the 90s expected a 386 or 486. (This is the speed for
        // games that run in DOS's real mode; ones using DOS extenders
        // already get DOSBox's much faster protected-mode speed.) At
        // DOSBox's usual 286-class speed some crawl: Blackthorne's music
        // driver takes minutes to load
        // Memory: mid-90s games need more than DOSBox's 16 MB, but some of
        // their DOS extenders crash with 64 (Beneath a Steel Sky); later
        // games get 64
        if year >= 1996 { return ["cpu cpu_cycles": Self.speed486, "dosbox memsize": "64"] }
        if year >= 1993 { return ["cpu cpu_cycles": Self.speed486, "dosbox memsize": "32"] }
        if year >= 1990 { return ["cpu cpu_cycles": Self.speed386] }
        return [:]
    }

    /// Machines' speeds on DOSBox Staging's scale.
    public static let originalPCSpeed = "300"
    public static let speed386 = "8000"
    public static let speed486 = "20000"

    /// The speed the game starts at: its own (adjusted while playing), else
    /// its era's. Nil means DOSBox's usual speed.
    public var speed: String? {
        info.settings["cpu cpu_cycles"] ?? Self.eraSettings(year: year)["cpu cpu_cycles"]
    }

    /// Whether this program plays music on a Roland MT-32.
    public static func usesMT32(_ launcher: Launcher) -> Bool {
        let text = ([launcher.title] + (launcher.commands ?? [])).joined(separator: " ").lowercased()
        return text.contains("mt-32") || text.contains("mt32")
    }

    /// Whether the game offers Roland MT-32 music: an MT-32 option in its
    /// menu, or MT-32 drivers in its sound settings.
    public var supportsMT32: Bool {
        let mentions = { (text: String) in
            let lower = text.lowercased()
            return lower.contains("mt-32") || lower.contains("mt32")
        }
        if info.launchers.contains(where: { mentions($0.title) || ($0.commands ?? []).contains(where: mentions) }) {
            return true
        }
        guard let files = FileManager.default.enumerator(at: url.appending(path: "Drives"), includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]) else { return false }
        for case let file as URL in files {
            if files.level > 4 { files.skipDescendants(); continue }
            guard file.lastPathComponent.uppercased() == "MDI.INI",
                  let text = try? String(contentsOf: file, encoding: .isoLatin1) else { continue }
            if text.uppercased().contains("DRIVER      MT32") || text.uppercased().contains("DRIVER MT32") { return true }
        }
        return false
    }

    /// Sound cards the game is set up for, from its Miles Sound System
    /// settings (DIG.INI, MDI.INI): DOSBox only emulates a Gravis
    /// Ultrasound when asked, and games set up for one (Albion) quit
    /// without it.
    func soundCardSettings() -> [String: String] {
        let drives = url.appending(path: "Drives")
        guard let files = FileManager.default.enumerator(at: drives, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]) else { return [:] }
        for case let file as URL in files {
            if files.level > 4 { files.skipDescendants(); continue }
            guard ["DIG.INI", "MDI.INI"].contains(file.lastPathComponent.uppercased()),
                  let text = try? String(contentsOf: file, encoding: .isoLatin1) else { continue }
            let usesUltrasound = text.split(whereSeparator: \.isNewline).contains { line in
                let words = line.uppercased().split(whereSeparator: \.isWhitespace)
                return words.count >= 2 && words[0] == "DRIVER" && words[1].hasPrefix("ULTRA")
            }
            if usesUltrasound { return ["gus gus": "true"] }
        }
        return [:]
    }

    /// Menu scripts written for other DOSBox versions can set values this
    /// one doesn't accept ("mididevice=default", the system's synthesizer,
    /// is "coreaudio" here).
    static func fixingSettings(_ command: String) -> String {
        var command = command.replacingOccurrences(of: "mididevice=default", with: "mididevice=coreaudio",
                                                   options: .caseInsensitive)
        // Sound Canvas through a SoundFont: without one installed there'd be
        // no music, so use the Mac's General MIDI synthesizer
        if !SessionDefaults.hasSoundFont {
            for device in ["mididevice=fluidsynth", "mididevice=soundcanvas"] {
                command = command.replacingOccurrences(of: device, with: "mididevice=coreaudio", options: .caseInsensitive)
            }
        }
        return command
    }

    public func sessionArguments(_ start: Start = .game) throws -> [String] {
        let fileManager = FileManager.default
        var mounts: [String] = []
        for drive in info.drives {
            let source = url.appending(path: drive.path).path(percentEncoded: false)
            switch drive.kind {
            case .hardDisk:
                let saves = savesURL.appending(path: drive.letter, directoryHint: .isDirectory)
                try fileManager.createDirectory(at: saves, withIntermediateDirectories: true)
                mounts.append("@MOUNT \(drive.letter) \"\(source)\" >NUL")
                mounts.append("@MOUNT -t overlay \(drive.letter) \"\(saves.path(percentEncoded: false))\" >NUL")
            case .cdROM:
                let discs = ([drive.path] + (drive.moreDiscs ?? []))
                    .map { "\"\(url.appending(path: $0).path(percentEncoded: false))\"" }
                    .joined(separator: " ")
                mounts.append("@MOUNT \(drive.letter) \(discs) -t cdrom >NUL")
            case .floppy:
                mounts.append("@MOUNT \(drive.letter) \"\(source)\" -t floppy >NUL")
            }
        }
        var settings = Self.eraSettings(year: year).merging(soundCardSettings()) { $1 }
            .merging(info.settings) { $1 }
            .sorted { $0.key < $1.key }.flatMap { ["--set", "\($0.key)=\($0.value)"] }
        if let mapping = controllerMapping {
            settings += ["--set", "sdl mapperfile=\(mapping.path(percentEncoded: false))"]
        }
        let program: Launcher? = switch start {
        case .game: defaultLauncher
        case .launcher(let launcher): launcher
        case .prompt: nil
        }
        let exitsAfterwards = program != nil && info.closesWhenGameEnds
        if program == nil, let drive = info.drives.first {
            mounts.append("@\(drive.letter):")
        }
        return settings + StartupScript.arguments(
            mounts: mounts,
            title: name,
            programCommands: program?.commands?.map(Self.fixingSettings),
            detail: program == nil ? "Type DIR to see the game's files."
                : exitsAfterwards ? "Starting the game…" : "When the game ends, you'll be back at the DOS prompt.",
            program: program?.dosPath,
            exitsAfterwards: exitsAfterwards)
    }
}
