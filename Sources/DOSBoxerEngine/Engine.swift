import CDOSBoxerHost
import CDOSBoxerShared
import Foundation

/// Runs one DOS session: the emulator core, its sound, and the bridges to
/// the app (frames out through shared memory, input in through stdin).
///
/// One engine process runs one session and then exits; the core can't be
/// restarted within a process.
enum Engine {
    static func run(sharedFilePath: String, dosboxArguments: [String]) -> Never {
        guard let shared = mapSharedFile(at: sharedFilePath) else {
            FileHandle.standardError.write(Data("DOS Boxer Engine: can't open \(sharedFilePath)\n".utf8))
            exit(EX_IOERR)
        }

        // A window-less helper looks like background work to macOS, which
        // then delays its timers (App Nap) and frames arrive late. It's
        // running a game: ask for prompt scheduling
        Self.activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Running a DOS game")
        let audio = AudioOutput()
        Self.audio = audio
        let started = withCStrings(dosboxArguments) { argv in
            dbx_start(argv, Int32(dosboxArguments.count), publishFrame, sessionEnded, shared)
        }
        guard started else { exit(EX_SOFTWARE) }
        audio.start()

        readCommands()
        dispatchMain()
    }

    /// Keeps macOS from treating the session as background work.
    nonisolated(unsafe) private static var activity: NSObjectProtocol?

    /// The session's sound output (for volume changes from the app).
    nonisolated(unsafe) private static var audio: AudioOutput?

    /// Maps the frame buffer file the app created for this session.
    private static func mapSharedFile(at path: String) -> UnsafeMutableRawPointer? {
        let fd = open(path, O_RDWR)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let size = Int(dbx_shared_size())
        let base = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard let base, base != MAP_FAILED else { return nil }
        return base
    }

    /// Reads fixed-size commands from the app until it closes the pipe.
    private static func readCommands() {
        Thread.detachNewThread {
            var command = DBXCommand()
            let size = MemoryLayout<DBXCommand>.size
            while withUnsafeMutableBytes(of: &command, { readFully(into: $0.baseAddress!, count: size) }) {
                var payload = Data()
                if [DBXCommandMountFolder, DBXCommandTrigger, DBXCommandPaste, DBXCommandSetSpeed].map(\.rawValue).contains(command.type) {
                    let count = Int(command.b)
                    guard count > 0, count <= Int(DBX_COMMAND_MAX_PAYLOAD) else { break }
                    payload = Data(count: count)
                    guard payload.withUnsafeMutableBytes({ readFully(into: $0.baseAddress!, count: count) }) else { break }
                }
                handle(command, payload: payload)
            }
            // The app went away (or closed the pipe): shut down, and don't
            // linger if the core doesn't stop promptly.
            dbx_request_quit()
            sleep(3)
            _exit(0)
        }
    }

    /// Reads exactly `count` bytes from stdin; false at end of input.
    private static func readFully(into buffer: UnsafeMutableRawPointer, count: Int) -> Bool {
        var done = 0
        while done < count {
            let result = read(STDIN_FILENO, buffer + done, count - done)
            if result <= 0 { return false }
            done += result
        }
        return true
    }

    private static func handle(_ command: DBXCommand, payload: Data) {
        switch command.type {
        case DBXCommandKey.rawValue:
            dbx_key(command.a, command.b != 0)
        case DBXCommandMouseMotion.rawValue:
            dbx_mouse_motion(Float(command.a) / 100, Float(command.b) / 100)
        case DBXCommandMouseButton.rawValue:
            dbx_mouse_button(command.a, command.b != 0)
        case DBXCommandQuit.rawValue:
            dbx_request_quit()
        case DBXCommandTrigger.rawValue:
            if let action = String(data: payload, encoding: .utf8) {
                dbx_trigger(action)
            }
        case DBXCommandPause.rawValue:
            dbx_set_paused(command.a != 0)
        case DBXCommandSetSpeed.rawValue:
            let speeds = String(decoding: payload, as: UTF8.self).split(separator: " ").map(String.init)
            if speeds.count == 2 { dbx_set_speed(speeds[0], speeds[1]) }
        case DBXCommandPaste.rawValue:
            if let text = String(data: payload, encoding: .utf8) {
                dbx_paste_text(text)
            }
        case DBXCommandJoystick.rawValue:
            dbx_joystick(command.a >> 8, command.a & 0xFF, command.b)  // a: player<<12 | kind<<8 | index
        case DBXCommandVolume.rawValue:
            audio?.volume = Float(max(0, min(100, command.a))) / 100
        case DBXCommandMountFolder.rawValue:
            if let path = String(data: payload, encoding: .utf8) {
                dbx_mount_folder(CChar(command.a), path)
            }
        default:
            break
        }
    }
}

// The core calls these on its emulator thread; they must stay nonisolated
// file-level functions.

private let publishFrame: DBXFrameCallback = { context, frame in
    guard let context, let frame = frame?.pointee, let pixels = frame.pixels else { return }
    dbx_shared_publish(context, pixels, frame.width, frame.height, frame.bytes_per_row,
                       frame.display_aspect)
    // Report the speed too, so the app can remember changes made in the game
    let header = context.assumingMemoryBound(to: DBXSharedHeader.self)
    withUnsafeMutablePointer(to: &header.pointee.cpu_cycles) { real in
        withUnsafeMutablePointer(to: &header.pointee.cpu_cycles_protected) { protected in
            dbx_cpu_cycles(UnsafeMutableRawPointer(real).assumingMemoryBound(to: CChar.self), 32,
                           UnsafeMutableRawPointer(protected).assumingMemoryBound(to: CChar.self), 32)
        }
    }
}

private let sessionEnded: DBXExitCallback = { _, exitCode in
    // Skip static destructors: the core's teardown isn't safe to run twice.
    _exit(exitCode)
}

/// Runs `body` with a C `argv`-style array whose strings live for the call.
private func withCStrings<R>(_ strings: [String],
                             _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> R) -> R {
    let duplicated = strings.map { UnsafePointer(strdup($0)) }
    defer { duplicated.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
    return duplicated.withUnsafeBufferPointer { body($0.baseAddress) }
}
