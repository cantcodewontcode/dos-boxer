import CDOSBoxerShared
import MetalKit

/// Draws emulator frames into an MTKView, scaled to fit with the correct
/// display aspect ratio and letterboxed in black.
@MainActor
final class FrameRenderer: NSObject, MTKViewDelegate {
    private let emulator: Emulator
    private let commandQueue: MTLCommandQueue
    /// One pipeline per display look.
    private let pipelines: [DisplayLook: MTLRenderPipelineState]

    private var texture: MTLTexture?
    private var lastFrameCount: UInt64 = 0
    private var displayAspect = 4.0 / 3.0

    init?(view: MTKView, emulator: Emulator) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: frameShaderSource, options: nil)
        else { return nil }

        var pipelines: [DisplayLook: MTLRenderPipelineState] = [:]
        for look in DisplayLook.allCases {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "frameVertex")
            descriptor.fragmentFunction = library.makeFunction(name: look.fragmentFunction)
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            pipelines[look] = try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard pipelines[.crispPixels] != nil else { return nil }

        self.emulator = emulator
        self.commandQueue = queue
        self.pipelines = pipelines
        super.init()
        view.device = device
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(in: view) }
    }

    private func render(in view: MTKView) {
        uploadLatestFrame(device: view.device!)

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = commandQueue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }

        if let texture {
            let drawable = view.drawableSize
            let fitted = Self.aspectFit(aspect: displayAspect, in: drawable)
            encoder.setViewport(MTLViewport(originX: fitted.minX, originY: fitted.minY,
                                            width: fitted.width, height: fitted.height,
                                            znear: 0, zfar: 1))
            var outputSize = SIMD2<Float>(Float(fitted.width), Float(fitted.height))
            encoder.setRenderPipelineState(pipelines[emulator.displayLook] ?? pipelines[.crispPixels]!)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentBytes(&outputSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// Copies the newest frame from the engine's shared memory into the texture.
    private func uploadLatestFrame(device: MTLDevice) {
        guard let frames = emulator.frames else {
            texture = nil
            lastFrameCount = 0
            return
        }
        let count = dbx_shared_frame_count(frames.base)
        guard count != lastFrameCount else { return }

        var info = DBXSharedSlot()
        var pixels: UnsafePointer<UInt8>?
        var slot: UInt32 = 0
        var sequence: UInt64 = 0
        guard dbx_shared_latest(frames.base, &info, &pixels, &slot, &sequence), let pixels else { return }

        let width = Int(info.width), height = Int(info.height)
        if texture?.width != width || texture?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            texture = device.makeTexture(descriptor: descriptor)
        }
        texture?.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                         withBytes: pixels, bytesPerRow: Int(info.bytes_per_row))

        // If the engine overwrote the slot mid-copy, take it again next refresh
        if dbx_shared_is_unchanged(frames.base, slot, sequence) {
            lastFrameCount = count
            displayAspect = Double(info.display_aspect)
        }
    }

    /// The largest rectangle with `aspect` that fits centred in `size`.
    static func aspectFit(aspect: Double, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        var width = size.width
        var height = width / aspect
        if height > size.height {
            height = size.height
            width = height * aspect
        }
        return CGRect(x: ((size.width - width) / 2).rounded(), y: ((size.height - height) / 2).rounded(),
                      width: width.rounded(), height: height.rounded())
    }
}
