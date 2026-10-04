import AppKit
import CryptoKit
import DOSBoxerKit
import Foundation

struct LabOptions {
    var games = URL(filePath: "/Volumes/Games/DOS/ALL")
    var output = URL(filePath: "build/lab")
    var engine: URL?
    var jobs = 6
    var seconds = 20.0
    var limit = Int.max
    var filter: String?
    var year: String?
    /// Take every Nth game, to sample the whole collection evenly.
    var every = 1

    init<S: Sequence>(_ arguments: S) where S.Element == String {
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            let value = iterator.next() ?? ""
            switch flag {
            case "--games": games = URL(filePath: value)
            case "--out": output = URL(filePath: value)
            case "--engine": engine = URL(filePath: value)
            case "--jobs": jobs = max(1, Int(value) ?? jobs)
            case "--seconds": seconds = Double(value) ?? seconds
            case "--limit": limit = Int(value) ?? limit
            case "--filter": filter = value.lowercased()
            case "--year": year = value
            case "--every": every = max(1, Int(value) ?? 1)
            default: print("Unknown option \(flag)"); exit(EX_USAGE)
            }
        }
        // Default engine: next to this tool in the build products
        if engine == nil {
            let products = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent()
            engine = products.appending(path: "DOS Boxer.app/Contents/MacOS/DOS Boxer Engine")
        }
    }
}

/// What happened when a game was tried.
enum Outcome: String, Codable {
    /// Reached a graphics screen and kept running: the game starts.
    case graphics
    /// Running, but on a text screen: usually waiting for input (a version
    /// or language menu, "press any key"), sometimes an error message.
    case textScreen
    /// DOS shut down by itself before the time was up (the game quit).
    case endedEarly
    /// The engine crashed or reported an error.
    case crashed
    /// No program to start was found.
    case noLauncher
    case importFailed
}

struct ProgramPrint: Codable {
    var path: String
    var size: Int
    var sha256: String
}

struct LabResult: Codable {
    var archive: String
    var name: String
    var year: String?
    var outcome: Outcome
    var launcher: String?
    var launcherCount: Int
    var finalScreen: String?
    var frames: UInt64
    var seconds: Double
    var programs: [ProgramPrint]
    var note: String?
}

@MainActor
final class Lab {
    let options: LabOptions
    private var done: Set<String> = []
    private var resultsHandle: FileHandle?
    private var finished = 0
    private var tally: [Outcome: Int] = [:]

    private var resultsURL: URL { options.output.appending(path: "results.jsonl") }
    private var screensURL: URL { options.output.appending(path: "screens", directoryHint: .isDirectory) }
    private var scratchURL: URL { options.output.appending(path: "scratch", directoryHint: .isDirectory) }

    init(options: LabOptions) {
        self.options = options
    }

    func run() async {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: screensURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        loadPreviousResults()
        if !fileManager.fileExists(atPath: resultsURL.path(percentEncoded: false)) {
            fileManager.createFile(atPath: resultsURL.path(percentEncoded: false), contents: nil)
        }
        resultsHandle = try? FileHandle(forWritingTo: resultsURL)
        _ = try? resultsHandle?.seekToEnd()

        let archives = findArchives().enumerated()
            .filter { $0.offset % options.every == 0 }.map(\.element)
            .filter { !done.contains($0.lastPathComponent) }.prefix(options.limit)
        print("DOS Boxer Lab: \(archives.count) games to try (\(done.count) already done), \(options.jobs) at a time")

        var queue = Array(archives)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(options.jobs, queue.count) {
                let archive = queue.removeFirst()
                group.addTask { await self.tryAndRecord(archive) }
            }
            while await group.next() != nil {
                if !queue.isEmpty {
                    let archive = queue.removeFirst()
                    group.addTask { await self.tryAndRecord(archive) }
                }
            }
        }
        printSummary()
    }

    private func findArchives() -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: options.games, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "zip" }
            .filter { url in options.filter.map { url.lastPathComponent.lowercased().contains($0) } ?? true }
            .filter { url in options.year.map { url.lastPathComponent.contains("(\($0))") } ?? true }
            .sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
    }

    private func loadPreviousResults() {
        guard let text = try? String(contentsOf: resultsURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        for line in text.split(separator: "\n") {
            if let result = try? decoder.decode(LabResult.self, from: Data(line.utf8)) {
                done.insert(result.archive)
                tally[result.outcome, default: 0] += 1
            }
        }
    }

    private func tryAndRecord(_ archive: URL) async {
        let result = await tryGame(archive)
        finished += 1
        tally[result.outcome, default: 0] += 1
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(result) {
            try? resultsHandle?.write(contentsOf: data + Data("\n".utf8))
        }
        print(String(format: "%5d  %@ %@", finished, result.outcome.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0), result.name))
    }

    // MARK: Trying one game

    private func tryGame(_ archive: URL) async -> LabResult {
        let name = archive.deletingPathExtension().lastPathComponent
        let year = name.range(of: #"\((\d{4})\)"#, options: .regularExpression)
            .map { String(name[$0].dropFirst().dropLast()) }
        var result = LabResult(archive: archive.lastPathComponent, name: name, year: year, outcome: .importFailed,
                               launcher: nil, launcherCount: 0, finalScreen: nil, frames: 0, seconds: 0,
                               programs: [], note: nil)

        // Each game gets its own scratch library, deleted afterwards
        let library = scratchURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: library) }
        let gamebox: Gamebox
        do {
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            let imported = try await Task.detached { try GameLibrary.importGame(from: archive, into: library) }.value
            gamebox = try Gamebox.open(imported)
        } catch {
            result.note = error.localizedDescription
            return result
        }

        result.programs = await Task.detached { Self.fingerprints(of: gamebox) }.value
        result.launcherCount = gamebox.info.launchers.count
        guard let launcher = gamebox.defaultLauncher else {
            result.outcome = .noLauncher
            return result
        }
        result.launcher = launcher.dosPath

        let emulator = Emulator(engineURL: options.engine)
        do {
            emulator.start(arguments: ["--set", "mixer nosound=true"] + (try gamebox.sessionArguments(.game)))
        } catch {
            result.outcome = .crashed
            result.note = error.localizedDescription
            return result
        }

        let started = Date()
        var sawGraphics = false
        var graphicsAt: Date?
        var lastFrame: SharedFrames.Frame?
        while Date().timeIntervalSince(started) < options.seconds {
            try? await Task.sleep(for: .milliseconds(500))
            if case .stopped = emulator.state { break }
            if let frame = emulator.frames?.latestFrame() {
                lastFrame = frame
                if !Self.isTextMode(frame) && !sawGraphics {
                    sawGraphics = true
                    graphicsAt = Date()
                }
            }
            // Once graphics appear, give the game a few seconds to settle
            if let graphicsAt, Date().timeIntervalSince(graphicsAt) > 4 { break }
        }
        result.seconds = Date().timeIntervalSince(started)
        result.frames = lastFrame?.count ?? 0

        switch emulator.state {
        case .stopped(let code):
            result.outcome = code == 0 ? (sawGraphics ? .graphics : .endedEarly) : .crashed
            if code != 0 { result.note = "Engine exit code \(code)" }
        default:
            result.outcome = sawGraphics ? .graphics : .textScreen
        }

        if let lastFrame {
            result.finalScreen = "\(lastFrame.width)x\(lastFrame.height)"
            saveThumbnail(lastFrame, named: name)
        }

        emulator.stop()
        for _ in 0..<20 {
            if case .stopped = emulator.state { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return result
    }

    /// 80-column VGA text is 720×400; 40-column text 360×400.
    private static func isTextMode(_ frame: SharedFrames.Frame) -> Bool {
        (frame.width == 720 || frame.width == 360) && frame.height == 400
    }

    /// Size and SHA-256 of every program in the game: the seed data for
    /// recognising games later.
    nonisolated private static func fingerprints(of gamebox: Gamebox) -> [ProgramPrint] {
        guard let drive = gamebox.info.drives.first(where: { $0.letter == "C" }) else { return [] }
        let root = gamebox.url.appending(path: drive.path, directoryHint: .isDirectory).resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return []
        }
        var prints: [ProgramPrint] = []
        for case let file as URL in enumerator where ["exe", "com", "bat"].contains(file.pathExtension.lowercased()) {
            guard let data = try? Data(contentsOf: file) else { continue }
            let relative = file.resolvingSymlinksInPath().pathComponents.dropFirst(root.pathComponents.count)
            prints.append(ProgramPrint(path: relative.joined(separator: "/"), size: data.count,
                                       sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
        }
        return prints.sorted { $0.path < $1.path }
    }

    /// A 320-pixel-wide PNG of the last frame, shown at 4:3.
    private func saveThumbnail(_ frame: SharedFrames.Frame, named name: String) {
        let provider = CGDataProvider(data: frame.pixels as CFData)
        guard let provider,
              let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: frame.bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let context = CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 320, height: 240))
        guard let thumbnail = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: thumbnail)
        let safe = name.replacingOccurrences(of: "/", with: "-")
        try? rep.representation(using: .png, properties: [:])?
            .write(to: screensURL.appending(path: "\(safe).png"))
    }

    private func printSummary() {
        let total = tally.values.reduce(0, +)
        print("\nDOS Boxer Lab: \(total) games tried")
        for outcome in [Outcome.graphics, .textScreen, .endedEarly, .crashed, .noLauncher, .importFailed] {
            let count = tally[outcome, default: 0]
            let percent = total > 0 ? Double(count) / Double(total) * 100 : 0
            print(String(format: "  %@ %6d  %5.1f%%", outcome.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0), count, percent))
        }
    }
}
