import AppKit

extension SharedFrames.Frame {
    /// The frame as an image, scaled to `size` (4:3 by default, like a CRT).
    public func image(size: CGSize? = nil) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: pixels as CFData),
              let raw = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: bytesPerRow, space: colorSpace,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let target = size ?? CGSize(width: max(width, 640), height: max(width, 640) * 3 / 4)
        guard let context = CGContext(data: nil, width: Int(target.width), height: Int(target.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(raw, in: CGRect(origin: .zero, size: target))
        return context.makeImage()
    }

    /// PNG data of the frame at 4:3.
    public func pngData() -> Data? {
        guard let image = image() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
