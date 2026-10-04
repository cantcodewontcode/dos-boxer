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

    /// How the screen is drawn right now.
    @ObservationIgnored public var displayLook: DisplayLook = .appDefault

    /// True while the game is paused.
    public private(set) var isPaused = false

    /// True while the DOS screen has captured the mouse.
    public internal(set) var isMouseLocked = false

    /// The current session's frames, or nil when nothing is running.
    @ObservationIgnored public private(set) var frames: SharedFrames?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var commands: FileHandle?
    /// Arguments for a session to start once the current one has stopped.
    @ObservationIgnored private var pendingStart: [String]?

    /// The engine helper to run; nil means the one inside this app.
    private let engineURL: URL?

    public init(engineURL: URL? = nil) {
        self.engineURL = engineURL
        SharedFrames.removeLeftoversOnce()
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
        guard let engineURL = engineURL ?? Bundle.main.url(forAuxiliaryExecutable: "DOS Boxer Engine") else {
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
        process.arguments = [frames.fileURL.path(percentEncoded: false)] + SessionDefaults.arguments() + arguments
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
        if volume != 1 { sendVolume() }
    }

    private func sessionEnded(process finished: Process, exitCode: Int32) {
        guard finished === process else { return }
        isMouseLocked = false
        isPaused = false
        process = nil
        commands = nil
        frames = nil
        state = .stopped(exitCode: exitCode)

        if let arguments = pendingStart {
            pendingStart = nil
            launch(arguments: arguments)
        }
    }

    /// Mounts `folder` as a DOS drive while DOS keeps running. If DOS is at
    /// the Z: prompt, it switches to the new drive. Returns false if there's
    /// no running session.
    @discardableResult
    public func mount(folder: URL, as driveLetter: Character = "C") -> Bool {
        let path = Data(folder.path(percentEncoded: false).utf8)
        guard state == .running, let letter = driveLetter.asciiValue,
              path.count <= Int(DBX_COMMAND_MAX_PAYLOAD) else { return false }
        send(DBXCommand(type: DBXCommandMountFolder.rawValue, a: Int32(letter), b: Int32(path.count)),
             payload: path)
        return true
    }

    /// Pauses or resumes the game (sound stops while paused).
    public func togglePause() {
        guard state == .running else { return }
        isPaused.toggle()
        send(DBXCommand(type: DBXCommandPause.rawValue, a: isPaused ? 1 : 0, b: 0))
    }

    /// Types `text` into DOS as if typed on the keyboard (printable
    /// characters, tabs and line breaks).
    public func paste(_ text: String) {
        let data = Data(text.utf8)
        guard data.count <= Int(DBX_COMMAND_MAX_PAYLOAD) else { return }
        send(DBXCommand(type: DBXCommandPaste.rawValue, a: 0, b: Int32(data.count)), payload: data)
    }

    /// Makes the game run faster or slower (the emulated CPU's speed).
    public func changeSpeed(faster: Bool) {
        trigger(faster ? "cycleup" : "cycledown")
    }

    /// Switches drive D to the game's next disc (multi-disc games).
    public func nextDisc() {
        trigger("swapimg")
    }

    /// Game sound volume, 0–1. Kept for the session and reapplied on restart.
    public var volume: Double = 1 {
        didSet { sendVolume() }
    }

    private func sendVolume() {
        send(DBXCommand(type: DBXCommandVolume.rawValue, a: Int32((volume * 100).rounded()), b: 0))
    }

    private func trigger(_ action: String) {
        let name = Data(action.utf8)
        send(DBXCommand(type: DBXCommandTrigger.rawValue, a: 0, b: Int32(name.count)), payload: name)
    }

    /// The newest frame, e.g. for screenshots.
    public func currentFrame() -> SharedFrames.Frame? {
        frames?.latestFrame()
    }

    // MARK: Input

    /// Game controller axis 0–5 (XInput order), value -1…1.
    func joystickAxis(_ index: Int32, _ value: Float) {
        let scaled = Int32((max(-1, min(1, value)) * 32767).rounded())
        send(DBXCommand(type: DBXCommandJoystick.rawValue, a: 0 << 8 | index, b: scaled))
    }

    /// Game controller button 0–10 (XInput order).
    func joystickButton(_ index: Int32, _ isPressed: Bool) {
        send(DBXCommand(type: DBXCommandJoystick.rawValue, a: 1 << 8 | index, b: isPressed ? 1 : 0))
    }

    /// Game controller d-pad: up 1 | right 2 | down 4 | left 8.
    func joystickHat(_ value: Int32) {
        send(DBXCommand(type: DBXCommandJoystick.rawValue, a: 2 << 8, b: value))
    }

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

    private func send(_ command: DBXCommand, payload: Data = Data()) {
        guard state == .running || state == .stopping, let commands else { return }
        var command = command
        let data = withUnsafeBytes(of: &command) { Data($0) } + payload
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

    /// Deletes frame files left behind if the app was force-quit, once per
    /// launch (before any session of ours exists; later it would delete
    /// files that running sessions are using).
    @MainActor static func removeLeftoversOnce() {
        guard !hasRemovedLeftovers else { return }
        hasRemovedLeftovers = true
        removeLeftovers()
    }

    @MainActor private static var hasRemovedLeftovers = false

    static func removeLeftovers() {
        let folder = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for name in names where name.hasPrefix(filePrefix) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    private static let filePrefix = "dosboxer-frames-"

    /// A copy of the newest frame (BGRA pixels), or nil if none has arrived.
    public struct Frame: Sendable {
        public var pixels: Data
        public var width: Int
        public var height: Int
        public var bytesPerRow: Int
        /// How many frames the engine has produced so far.
        public var count: UInt64
    }

    public func latestFrame() -> Frame? {
        var info = DBXSharedSlot()
        var pixels: UnsafePointer<UInt8>?
        var slot: UInt32 = 0
        var sequence: UInt64 = 0
        let count = dbx_shared_frame_count(base)
        guard dbx_shared_latest(base, &info, &pixels, &slot, &sequence), let pixels else { return nil }
        let data = Data(bytes: pixels, count: Int(info.bytes_per_row) * Int(info.height))
        guard dbx_shared_is_unchanged(base, slot, sequence) else { return nil }
        return Frame(pixels: data, width: Int(info.width), height: Int(info.height),
                     bytesPerRow: Int(info.bytes_per_row), count: count)
    }

    deinit {
        munmap(base, size)
        unlink(fileURL.path(percentEncoded: false))
    }
}
