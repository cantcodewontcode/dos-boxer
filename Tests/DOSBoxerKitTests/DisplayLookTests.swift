import Metal
import Testing
@testable import DOSBoxerKit

struct DisplayLookTests {
    /// The shaders are compiled when the app runs, so check here that every
    /// look's shader compiles and links.
    @Test func everyLookHasAWorkingShader() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeLibrary(source: frameShaderSource, options: nil)
        for look in DisplayLook.allCases {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "frameVertex")
            descriptor.fragmentFunction = library.makeFunction(name: look.fragmentFunction)
            #expect(descriptor.fragmentFunction != nil, "\(look) has no shader")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            _ = try device.makeRenderPipelineState(descriptor: descriptor)
        }
    }
}

import AppKit
import MetalKit

extension DisplayLookTests {
    /// Development aid: with DBX_RENDER_LOOKS=<image> and DBX_RENDER_OUT=<folder>,
    /// renders the image through every look into PNGs for eyeballing.
    @Test func renderLooksForInspection() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment["DBX_RENDER_LOOKS"], let output = environment["DBX_RENDER_OUT"] else { return }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeLibrary(source: frameShaderSource, options: nil)
        let source = try MTKTextureLoader(device: device).newTexture(URL: URL(filePath: input),
                                                                      options: [.SRGB: false])
        let size = (width: 1280, height: 960)
        for look in DisplayLook.allCases {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "frameVertex")
            descriptor.fragmentFunction = library.makeFunction(name: look.fragmentFunction)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: size.width, height: size.height, mipmapped: false)
            targetDescriptor.usage = [.renderTarget, .shaderRead]
            let target = try #require(device.makeTexture(descriptor: targetDescriptor))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let queue = try #require(device.makeCommandQueue())
            let commands = try #require(queue.makeCommandBuffer())
            let encoder = try #require(commands.makeRenderCommandEncoder(descriptor: pass))
            var outputSize = SIMD2<Float>(Float(size.width), Float(size.height))
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(&outputSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            var pixels = [UInt8](repeating: 0, count: size.width * size.height * 4)
            target.getBytes(&pixels, bytesPerRow: size.width * 4,
                            from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size.width, pixelsHigh: size.height,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: size.width * 4, bitsPerPixel: 32)!
            for i in stride(from: 0, to: pixels.count, by: 4) {  // BGRA → RGBA
                rep.bitmapData![i] = pixels[i + 2]; rep.bitmapData![i + 1] = pixels[i + 1]
                rep.bitmapData![i + 2] = pixels[i]; rep.bitmapData![i + 3] = 255
            }
            try rep.representation(using: .png, properties: [:])!
                .write(to: URL(filePath: output).appending(path: "\(look.rawValue).png"))
        }
    }
}
