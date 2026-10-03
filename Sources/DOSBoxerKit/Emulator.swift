import CDOSBoxerShared
import Foundation
import Observation

/// Runs DOS sessions for the UI.
///
/// Each session runs in its own helper process (`DOS Boxer Engine`), because
/// the emulator core can only run once per process. Starting again (to
/// restart, or to use a different game folder) replaces the helper; the
/// window stays put. Frames come back through shared memory (`SharedFrames`);
/// keyboard and mouse input go to the helper over a pipe.
@MainActor
@Observable
public final class Emulator {
    public enum State: Equatable, Sendable {
        case idle
        case running
        case stopping
        case stopped(exitCode: Int32)
    }

    public private(set) var state: State = .idle

    /// True while the DOS screen has captured the mouse.
    public internal(set) var isMouseLocked = false

    /// The current session's frames, or nil when nothing is running.
    @ObservationIgnored public private(set) var frames: SharedFrames?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var commands: FileHandle?
    /// Arguments for a session to start once the current one has stopped.
    @ObservationIgnored private var pendingStart: [String]?

    public init() {
        SharedFrames.removeLeftovers()
    }

    public var isRunning: Bool { state == .running }

    /// Starts DOS with dosbox command-line arguments, e.g.
    /// `["-c", "MOUNT C /path", "-c", "C:"]`. If a session is already running,
    /// it's stopped first and the new one starts as soon as it has quit.
    public func start(arguments: [String] = []) {
        switch state {
        case .running, .stopping:
            pendingStart = arguments
            stop()
        case .idle, .stopped:
            launch(arguments: arguments)
        }
    }

    /// Stops the current session.
    public func stop() {
        guard let process, state == .running || state == .stopping else { return }
        state = .stopping
        send(DBXCommand(type: DBXCommandQuit.rawValue, a: 0, b: 0))

        // If the helper doesn't finish within a few seconds, end it.
        Task { [weak self, weak process] in
            try? await Task.sleep(for: .seconds(3))
            guard let process, process.isRunning, self?.process === process else { return }
            process.terminate()
        }
    }

    private func launch(arguments: [String]) {
        guard let engineURL = Bundle.main.url(forAuxiliaryExecutable: "DOS Boxer Engine") else {
            print("DOS Boxer: the engine helper is missing from the app bundle")
            state = .stopped(exitCode: -1)
            return
        }
        guard let frames = SharedFrames() else {
            state = .stopped(exitCode: -1)
            return
        }

        let input = Pipe()
        let process = Process()
        process.executableURL = engineURL
        process.arguments = [frames.fileURL.path(percentEncoded: false)] + arguments
        process.standardInput = input
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor in self?.sessionEnded(process: finished, exitCode: code) }
        }

        do {
            try process.run()
        } catch {
            print("DOS Boxer: couldn't start the engine: \(error)")
            state = .stopped(exitCode: -1)
            return
        }

        self.frames = frames
        self.process = process
        self.commands = input.fileHandleForWriting
        state = .running
    }

    private func sessionEnded(process finished: Process, exitCode: Int32) {
        guard finished === process else { return }
        isMouseLocked = false
        process = nil
        commands = nil
        frames = nil
        state = .stopped(exitCode: exitCode)

        if let arguments = pendingStart {
            pendingStart = nil
            launch(arguments: arguments)
        }
    }

    // MARK: Input

    public func key(scancode: Int32, isDown: Bool) {
        send(DBXCommand(type: DBXCommandKey.rawValue, a: scancode, b: isDown ? 1 : 0))
    }

    public func mouseMoved(dx: Double, dy: Double) {
        send(DBXCommand(type: DBXCommandMouseMotion.rawValue,
                        a: Int32((dx * 100).rounded()), b: Int32((dy * 100).rounded())))
    }

    /// 1 = left, 2 = middle, 3 = right.
    public func mouseButton(_ button: Int32, isDown: Bool) {
        send(DBXCommand(type: DBXCommandMouseButton.rawValue, a: button, b: isDown ? 1 : 0))
    }

    private func send(_ command: DBXCommand) {
        guard state == .running || state == .stopping, let commands else { return }
        var command = command
        let data = withUnsafeBytes(of: &command) { Data($0) }
        try? commands.write(contentsOf: data)
    }
}

/// The memory-mapped frame buffer for one session, shared with its engine
/// process. The file lives in the app's temporary folder and is removed when
/// the session ends.
public final class SharedFrames {
    let fileURL: URL
    let base: UnsafeMutableRawPointer
    private let size: Int

    init?() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(Self.filePrefix)\(UUID().uuidString)")
        let size = Int(dbx_shared_size())
        let fd = open(url.path(percentEncoded: false), O_RDWR | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard ftruncate(fd, off_t(size)) == 0,
              let base = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
              base != MAP_FAILED else {
            unlink(url.path(percentEncoded: false))
            return nil
        }
        dbx_shared_init(base)
        self.fileURL = url
        self.base = base
        self.size = size
    }

    /// Deletes frame files left behind if the app was force-quit. Only one
    /// copy of the app uses this folder, so anything there now is stale.
    static func removeLeftovers() {
        let folder = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for name in names where name.hasPrefix(filePrefix) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    private static let filePrefix = "dosboxer-frames-"

    deinit {
        munmap(base, size)
        unlink(fileURL.path(percentEncoded: false))
    }
}
