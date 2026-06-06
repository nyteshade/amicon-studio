import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO

public extension RGBAImage {
    /// Decodes any image format ImageIO understands (PNG, JPEG, TIFF, HEIC, GIF,
    /// BMP, …) into a straight (non-premultiplied) RGBA buffer.
    init?(contentsOf url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.init(cgImage: cg)
    }

    init?(data: Data) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.init(cgImage: cg)
    }

    init?(cgImage cg: CGImage) {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        // kCGImageAlphaPremultipliedLast then un-premultiply, so colours under
        // transparent areas survive for the quantiser/glow.
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = buf.withUnsafeMutableBytes({ ptr -> CGContext? in
            CGContext(data: ptr.baseAddress, width: w, height: h,
                      bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: cs, bitmapInfo: info)
        }) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in 0..<(w * h) {
            let a = buf[i * 4 + 3]
            if a > 0 && a < 255 {
                buf[i * 4]     = UInt8(min(255, Int(buf[i * 4])     * 255 / Int(a)))
                buf[i * 4 + 1] = UInt8(min(255, Int(buf[i * 4 + 1]) * 255 / Int(a)))
                buf[i * 4 + 2] = UInt8(min(255, Int(buf[i * 4 + 2]) * 255 / Int(a)))
            }
        }
        self.init(width: w, height: h, pixels: buf)
    }

    /// Encodes the buffer as PNG (used to preview composed icons and to persist
    /// originals inside a project document).
    func pngData() -> Data? {
        let w = width, h = height
        // Pre-multiply alpha into a scratch buffer for a correct PNG.
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let a = Int(pixels[i * 4 + 3])
            buf[i * 4 + 0] = UInt8(Int(pixels[i * 4 + 0]) * a / 255)
            buf[i * 4 + 1] = UInt8(Int(pixels[i * 4 + 1]) * a / 255)
            buf[i * 4 + 2] = UInt8(Int(pixels[i * 4 + 2]) * a / 255)
            buf[i * 4 + 3] = UInt8(a)
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        // Do all CGContext/CGImage work inside the buffer's lifetime.
        return buf.withUnsafeMutableBytes { ptr -> Data? in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: cs, bitmapInfo: info),
                  let cg = ctx.makeImage() else { return nil }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, cg, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return out as Data
        }
    }
}
#endif
