import Synchronization

/// The most recent frame from the emulator, handed from the emulator thread to
/// the renderer. The emulator writes; the renderer reads on each display refresh.
public final class FrameBuffer: Sendable {
    public struct Snapshot: Sendable {
        public var pixels: [UInt8]
        public var width: Int
        public var height: Int
        public var bytesPerRow: Int
        /// Width ÷ height the frame should be displayed at.
        public var displayAspect: Double
        /// Increments with every new frame, so readers can skip unchanged ones.
        public var generation: UInt64
    }

    private let state = Mutex(Snapshot(pixels: [], width: 0, height: 0, bytesPerRow: 0,
                                       displayAspect: 4.0 / 3.0, generation: 0))

    public init() {}

    /// Copies a frame in. Called on the emulator thread.
    func store(pixels: UnsafePointer<UInt8>, width: Int, height: Int,
               bytesPerRow: Int, displayAspect: Double) {
        let byteCount = bytesPerRow * height
        state.withLock { snapshot in
            if snapshot.pixels.count != byteCount {
                snapshot.pixels = [UInt8](repeating: 0, count: byteCount)
            }
            snapshot.pixels.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress!.update(from: pixels, count: byteCount)
            }
            snapshot.width = width
            snapshot.height = height
            snapshot.bytesPerRow = bytesPerRow
            snapshot.displayAspect = displayAspect
            snapshot.generation &+= 1
        }
    }

    /// Calls `body` with the latest frame if it's newer than `generation`.
    /// Runs under the lock, so keep `body` short (a texture upload).
    func withFrame(newerThan generation: UInt64, _ body: (borrowing Snapshot) -> Void) {
        state.withLock { snapshot in
            guard snapshot.generation != generation, snapshot.width > 0 else { return }
            body(snapshot)
        }
    }

    /// True when there's no frame to show (not started, or stopped).
    var isEmpty: Bool {
        state.withLock { $0.width == 0 }
    }

    func reset() {
        state.withLock { $0.width = 0; $0.generation &+= 1 }
    }
}
