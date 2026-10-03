import MetalKit

/// Draws emulator frames into an MTKView, scaled to fit with the correct
/// display aspect ratio and letterboxed in black.
@MainActor
final class FrameRenderer: NSObject, MTKViewDelegate {
    private let frames: FrameBuffer
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private var texture: MTLTexture?
    private var lastGeneration: UInt64 = 0
    private var displayAspect = 4.0 / 3.0

    init?(view: MTKView, frames: FrameBuffer) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: frameShaderSource, options: nil)
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "frameVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "frameFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }

        self.frames = frames
        self.commandQueue = queue
        self.pipeline = pipeline
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
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentBytes(&outputSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    private func uploadLatestFrame(device: MTLDevice) {
        frames.withFrame(newerThan: lastGeneration) { frame in
            lastGeneration = frame.generation
            displayAspect = frame.displayAspect

            if texture?.width != frame.width || texture?.height != frame.height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: frame.width, height: frame.height, mipmapped: false)
                descriptor.usage = .shaderRead
                descriptor.storageMode = .shared
                texture = device.makeTexture(descriptor: descriptor)
            }
            frame.pixels.withUnsafeBytes { bytes in
                texture?.replace(region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                                 mipmapLevel: 0, withBytes: bytes.baseAddress!,
                                 bytesPerRow: frame.bytesPerRow)
            }
        }
        if frames.isEmpty { texture = nil }
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
