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

        let audio = AudioOutput()
        let started = withCStrings(dosboxArguments) { argv in
            dbx_start(argv, Int32(dosboxArguments.count), publishFrame, sessionEnded, shared)
        }
        guard started else { exit(EX_SOFTWARE) }
        audio.start()

        readCommands()
        dispatchMain()
    }

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
            while withUnsafeMutableBytes(of: &command, { read(STDIN_FILENO, $0.baseAddress, size) }) == size {
                handle(command)
            }
            // The app went away (or closed the pipe): shut down, and don't
            // linger if the core doesn't stop promptly.
            dbx_request_quit()
            sleep(3)
            _exit(0)
        }
    }

    private static func handle(_ command: DBXCommand) {
        switch command.type {
        case DBXCommandKey.rawValue:
            dbx_key(command.a, command.b != 0)
        case DBXCommandMouseMotion.rawValue:
            dbx_mouse_motion(Float(command.a) / 100, Float(command.b) / 100)
        case DBXCommandMouseButton.rawValue:
            dbx_mouse_button(command.a, command.b != 0)
        case DBXCommandQuit.rawValue:
            dbx_request_quit()
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
