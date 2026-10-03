import CDOSBoxerHost
import Foundation
import Observation

/// Owns the embedded DOS emulator: starting, stopping and feeding it input.
///
/// The emulator itself runs on its own thread inside the core library; this
/// class is the main-actor-facing handle the UI talks to.
///
/// The core can only run **once per process**: it keeps process-wide state
/// that isn't reset after it shuts down. Check `canStart`; to run again, start
/// a new process. (The full app will run each game in its own helper process.)
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
    public let frames = FrameBuffer()
    public let audio: AudioOutput

    /// False once the emulator has run in this process.
    public private(set) var canStart = true

    /// Bridges C callbacks (which can't capture) back to this instance.
    fileprivate final class Bridge: Sendable {
        let frames: FrameBuffer
        let onExit: @Sendable (Int32) -> Void
        init(frames: FrameBuffer, onExit: @escaping @Sendable (Int32) -> Void) {
            self.frames = frames
            self.onExit = onExit
        }
    }
    private var bridge: Unmanaged<Bridge>?

    public init() {
        audio = AudioOutput()
    }

    public var isRunning: Bool { state == .running }

    /// Starts the emulator with dosbox command-line arguments,
    /// e.g. `["-c", "MOUNT C /path", "-c", "C:"]`.
    public func start(arguments: [String] = []) {
        guard canStart else { return }

        let bridge = Unmanaged.passRetained(Bridge(frames: frames) { [weak self] code in
            Task { @MainActor in self?.didExit(code: code) }
        })
        self.bridge = bridge

        let started = withCStrings(arguments) { argv in
            dbx_start(argv, Int32(arguments.count), emulatorFrameCallback, emulatorExitCallback,
                      bridge.toOpaque())
        }

        if started {
            canStart = false
            state = .running
            audio.start()
        } else {
            bridge.release()
            self.bridge = nil
        }
    }

    public func stop() {
        guard state == .running else { return }
        state = .stopping
        dbx_request_quit()
    }

    private func didExit(code: Int32) {
        audio.stop()
        frames.reset()
        bridge?.release()
        bridge = nil
        state = .stopped(exitCode: code)
    }

    // MARK: Input

    public func key(scancode: Int32, isDown: Bool) {
        dbx_key(scancode, isDown)
    }

    public func mouseMoved(dx: Double, dy: Double) {
        dbx_mouse_motion(Float(dx), Float(dy))
    }

    /// 1 = left, 2 = middle, 3 = right.
    public func mouseButton(_ button: Int32, isDown: Bool) {
        dbx_mouse_button(button, isDown)
    }
}

// The core calls these on its emulator thread, so they must not be
// main-actor isolated (closures written inside `Emulator` would be).

private let emulatorFrameCallback: DBXFrameCallback = { context, frame in
    guard let context, let frame = frame?.pointee, let pixels = frame.pixels else { return }
    let bridge = Unmanaged<Emulator.Bridge>.fromOpaque(context).takeUnretainedValue()
    bridge.frames.store(pixels: pixels,
                        width: Int(frame.width),
                        height: Int(frame.height),
                        bytesPerRow: Int(frame.bytes_per_row),
                        displayAspect: Double(frame.display_aspect))
}

private let emulatorExitCallback: DBXExitCallback = { context, exitCode in
    guard let context else { return }
    Unmanaged<Emulator.Bridge>.fromOpaque(context).takeUnretainedValue().onExit(exitCode)
}

/// Runs `body` with a C `argv`-style array whose strings live for the call.
private func withCStrings<R>(_ strings: [String],
                             _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> R) -> R {
    let duplicated = strings.map { UnsafePointer(strdup($0)) }
    defer { duplicated.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
    return duplicated.withUnsafeBufferPointer { body($0.baseAddress) }
}
