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
            while withUnsafeMutableBytes(of: &command, { readFully(into: $0.baseAddress!, count: size) }) {
                var payload = Data()
                if command.type == DBXCommandMountFolder.rawValue {
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
        case DBXCommandMountFolder.rawValue:
            mountFolder(bookmark: payload, driveLetter: CChar(command.a))
        default:
            break
        }
    }
}

extension Engine {
    /// Folders this session has been given access to; kept open until exit.
    nonisolated(unsafe) private static var accessedFolders: [URL] = []

    /// Resolves a folder the app handed over and mounts it as a DOS drive.
    /// The bookmark carries the sandbox permission the user granted the app
    /// when they picked the folder.
    private static func mountFolder(bookmark: Data, driveLetter: CChar) {
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                    bookmarkDataIsStale: &isStale) else {
            FileHandle.standardError.write(Data("DOS Boxer Engine: couldn't open the folder bookmark\n".utf8))
            return
        }
        if folder.startAccessingSecurityScopedResource() {
            accessedFolders.append(folder)
        }
        dbx_mount_folder(driveLetter, folder.path(percentEncoded: false))
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
