import Foundation

/// A simple 32-bit RGBA pixel buffer, row-major, 4 bytes per pixel.
///
/// This is the common currency for the whole kit: every encoder takes an
/// `RGBAImage`. It is deliberately platform-agnostic (no AppKit / CoreGraphics)
/// so the kit and its tests build on Linux as well as macOS. Loading from
/// real image files lives in `ImageLoading.swift`, guarded for Apple platforms.
public struct RGBAImage: Equatable {
    public let width: Int
    public let height: Int
    /// `width * height * 4` bytes, ordered R, G, B, A.
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4,
                     "pixel buffer size must equal width * height * 4")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Creates a fully transparent image.
    public init(width: Int, height: Int) {
        self.init(width: width, height: height,
                  pixels: [UInt8](repeating: 0, count: width * height * 4))
    }

    @inline(__always)
    public func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }

    @inline(__always)
    public mutating func setPixel(_ x: Int, _ y: Int,
                                  _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) {
        let i = (y * width + x) * 4
        pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b; pixels[i + 3] = a
    }

    /// Nearest-neighbour resize. Amiga icons are small; quality here is not
    /// critical, and nearest-neighbour preserves hard edges and palettes well.
    public func resized(to newWidth: Int, to newHeight: Int) -> RGBAImage {
        guard newWidth != width || newHeight != height else { return self }
        var out = RGBAImage(width: newWidth, height: newHeight)
        for y in 0..<newHeight {
            let sy = min(height - 1, y * height / newHeight)
            for x in 0..<newWidth {
                let sx = min(width - 1, x * width / newWidth)
                let p = pixel(sx, sy)
                out.setPixel(x, y, p.r, p.g, p.b, p.a)
            }
        }
        return out
    }
}

public extension RGBAImage {
    /// Produces a "selected"/clicked variant by adding a soft coloured **glow**
    /// around the opaque silhouette — the hallmark of OS3.5+ GlowIcons in their
    /// selected state.
    ///
    /// The glow is grown outwards from opaque pixels by `radius`, with the
    /// supplied colour and a linear alpha falloff. Existing opaque pixels are
    /// left untouched; the glow only fills surrounding transparent area.
    ///
    /// - Parameters:
    ///   - radius: glow thickness in pixels (1...).
    ///   - color: glow colour as (r, g, b). Classic GlowIcons use a warm orange
    ///            (`0xFF, 0x8B, 0x00`) or a bright blue; orange is the default.
    ///   - alphaThreshold: pixels with alpha >= this count as opaque source.
    func addingGlow(radius: Int = 4,
                    color: (r: UInt8, g: UInt8, b: UInt8) = (0xFF, 0x8B, 0x00),
                    alphaThreshold: UInt8 = 128) -> RGBAImage {
        guard radius > 0 else { return self }
        // Distance (in pixels) from each pixel to the nearest opaque pixel.
        // Computed with a simple two-pass approximate distance transform.
        let w = width, h = height
        let big = w + h + 1
        var dist = [Int](repeating: big, count: w * h)
        for y in 0..<h {
            for x in 0..<w where pixel(x, y).a >= alphaThreshold {
                dist[y * w + x] = 0
            }
        }
        // Forward pass (top-left to bottom-right).
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if x > 0 { dist[i] = min(dist[i], dist[i - 1] + 1) }
                if y > 0 { dist[i] = min(dist[i], dist[i - w] + 1) }
            }
        }
        // Backward pass (bottom-right to top-left).
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let i = y * w + x
                if x < w - 1 { dist[i] = min(dist[i], dist[i + 1] + 1) }
                if y < h - 1 { dist[i] = min(dist[i], dist[i + w] + 1) }
            }
        }

        var out = self
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let d = dist[i]
                guard d > 0 && d <= radius else { continue } // 0 = opaque source, skip
                let existing = pixel(x, y)
                guard existing.a < alphaThreshold else { continue } // don't overwrite art
                // Linear falloff: strongest next to the silhouette.
                let strength = Double(radius - d + 1) / Double(radius)
                let a = UInt8(max(0, min(255, Int(strength * 255))))
                out.setPixel(x, y, color.r, color.g, color.b, a)
            }
        }
        return out
    }
}
