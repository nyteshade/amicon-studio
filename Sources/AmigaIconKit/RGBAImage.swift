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

    /// Resamples to a new size with the chosen `filter`:
    ///   - `.nearest`: crisp, hard-edged — best for pixel art and upscaling.
    ///   - `.smooth`:  alpha-weighted area averaging — best for shrinking photos
    ///     to icon size (avoids the aliasing nearest-neighbour produces). It
    ///     degrades to nearest-style sampling when enlarging, which keeps small
    ///     art crisp.
    public func resized(to newWidth: Int, to newHeight: Int,
                        filter: ResampleFilter = .nearest) -> RGBAImage {
        guard newWidth != width || newHeight != height else { return self }
        switch filter {
        case .nearest: return nearestResized(newWidth, newHeight)
        case .smooth:  return areaResampled(newWidth, newHeight)
        }
    }

    private func nearestResized(_ newWidth: Int, _ newHeight: Int) -> RGBAImage {
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

    /// Area-averaging resample. Each destination pixel averages the source
    /// rectangle it covers, weighting colour by alpha so colours under
    /// transparent pixels don't bleed dark halos into the result.
    public func areaResampled(_ newWidth: Int, _ newHeight: Int) -> RGBAImage {
        var out = RGBAImage(width: newWidth, height: newHeight)
        let sx = Double(width) / Double(newWidth)
        let sy = Double(height) / Double(newHeight)
        for ty in 0..<newHeight {
            let y0 = Int((Double(ty) * sy).rounded(.down))
            let y1 = min(height, max(y0 + 1, Int((Double(ty + 1) * sy).rounded(.up))))
            for tx in 0..<newWidth {
                let x0 = Int((Double(tx) * sx).rounded(.down))
                let x1 = min(width, max(x0 + 1, Int((Double(tx + 1) * sx).rounded(.up))))
                var ar = 0.0, ag = 0.0, ab = 0.0, asum = 0.0, n = 0.0
                for yy in y0..<y1 {
                    for xx in x0..<x1 {
                        let p = pixel(xx, yy)
                        let a = Double(p.a) / 255.0
                        ar += Double(p.r) * a; ag += Double(p.g) * a; ab += Double(p.b) * a
                        asum += a; n += 1
                    }
                }
                if n == 0 { continue }
                if asum > 0 {
                    out.setPixel(tx, ty, u8(ar / asum), u8(ag / asum), u8(ab / asum), u8(asum / n * 255))
                } // else leave fully transparent
            }
        }
        return out
    }
}

public extension RGBAImage {
    /// Draws a solid outline of `thickness` pixels hugging the opaque silhouette,
    /// behind the existing artwork (only transparent pixels within `thickness` of
    /// an opaque pixel are filled). Great for making icons read against any
    /// Workbench backdrop. Needs that much transparent margin around the art or
    /// the outline is clipped.
    func outlined(color: (r: UInt8, g: UInt8, b: UInt8), thickness: Int,
                  alphaThreshold: UInt8 = 128) -> RGBAImage {
        guard thickness > 0 else { return self }
        let w = width, h = height
        let big = w + h + 1
        var dist = [Int](repeating: big, count: w * h)
        for y in 0..<h {
            for x in 0..<w where pixel(x, y).a >= alphaThreshold { dist[y * w + x] = 0 }
        }
        // Two-pass approximate distance transform.
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if x > 0 { dist[i] = min(dist[i], dist[i - 1] + 1) }
                if y > 0 { dist[i] = min(dist[i], dist[i - w] + 1) }
            }
        }
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
                let d = dist[y * w + x]
                guard d > 0, d <= thickness, pixel(x, y).a < alphaThreshold else { continue }
                out.setPixel(x, y, color.r, color.g, color.b, 255)
            }
        }
        return out
    }

    /// Separable, alpha-weighted box blur of `radius` px (alpha weighting avoids
    /// dark halos bleeding from transparent areas). `radius <= 0` is a no-op.
    func boxBlurred(radius: Int) -> RGBAImage {
        guard radius > 0 else { return self }
        return blurPass(radius: radius, horizontal: true).blurPass(radius: radius, horizontal: false)
    }

    private func blurPass(radius: Int, horizontal: Bool) -> RGBAImage {
        var out = RGBAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                var ar = 0.0, ag = 0.0, ab = 0.0, asum = 0.0, n = 0.0
                for k in -radius...radius {
                    let sx = horizontal ? x + k : x
                    let sy = horizontal ? y : y + k
                    guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                    let p = pixel(sx, sy); let a = Double(p.a) / 255
                    ar += Double(p.r) * a; ag += Double(p.g) * a; ab += Double(p.b) * a
                    asum += a; n += 1
                }
                guard n > 0 else { continue }
                if asum > 0 { out.setPixel(x, y, u8(ar / asum), u8(ag / asum), u8(ab / asum), u8(asum / n * 255)) }
            }
        }
        return out
    }

    func flippedHorizontally() -> RGBAImage {
        var out = RGBAImage(width: width, height: height)
        for y in 0..<height { for x in 0..<width {
            let p = pixel(width - 1 - x, y); out.setPixel(x, y, p.r, p.g, p.b, p.a)
        } }
        return out
    }

    func flippedVertically() -> RGBAImage {
        var out = RGBAImage(width: width, height: height)
        for y in 0..<height { for x in 0..<width {
            let p = pixel(x, height - 1 - y); out.setPixel(x, y, p.r, p.g, p.b, p.a)
        } }
        return out
    }

    /// Rotates by 90° (dimensions swap).
    func rotated90(clockwise: Bool = true) -> RGBAImage {
        var out = RGBAImage(width: height, height: width)
        for y in 0..<height { for x in 0..<width {
            let p = pixel(x, y)
            if clockwise { out.setPixel(height - 1 - y, x, p.r, p.g, p.b, p.a) }
            else { out.setPixel(y, width - 1 - x, p.r, p.g, p.b, p.a) }
        } }
        return out
    }

    /// Applies flips then `quarters` clockwise 90° turns (non-destructive helper).
    func oriented(flipH: Bool, flipV: Bool, quarters: Int) -> RGBAImage {
        var img = self
        if flipH { img = img.flippedHorizontally() }
        if flipV { img = img.flippedVertically() }
        let q = ((quarters % 4) + 4) % 4
        for _ in 0..<q { img = img.rotated90(clockwise: true) }
        return img
    }

    /// Quantises each RGB channel to `levels` evenly-spaced steps (alpha kept),
    /// for a deliberate banded/retro look. `levels < 2` returns the image
    /// unchanged.
    func posterized(levels: Int) -> RGBAImage {
        guard levels >= 2 else { return self }
        let n = Double(levels - 1)
        var lut = [UInt8](repeating: 0, count: 256)
        for v in 0...255 { lut[v] = u8((Double(v) / 255.0 * n).rounded() / n * 255.0) }
        var out = self
        for i in 0..<(width * height) {
            out.pixels[i * 4] = lut[Int(pixels[i * 4])]
            out.pixels[i * 4 + 1] = lut[Int(pixels[i * 4 + 1])]
            out.pixels[i * 4 + 2] = lut[Int(pixels[i * 4 + 2])]
        }
        return out
    }

    /// A standalone layer (transparent except where filled) holding the opaque
    /// silhouette recoloured at `alpha` and offset by `(dx, dy)` — the building
    /// block for outer drop shadows. Compose it *behind* the art.
    func shadowLayer(dx: Int, dy: Int, color: (r: UInt8, g: UInt8, b: UInt8),
                     alpha: UInt8, alphaThreshold: UInt8 = 128) -> RGBAImage {
        var shadow = RGBAImage(width: width, height: height)
        guard alpha > 0 else { return shadow }
        for y in 0..<height {
            for x in 0..<width {
                let sx = x - dx, sy = y - dy
                guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                if pixel(sx, sy).a >= alphaThreshold {
                    shadow.setPixel(x, y, color.r, color.g, color.b, alpha)
                }
            }
        }
        return shadow
    }

    /// Like `shadowLayer` but with a soft, feathered edge: the offset silhouette
    /// is solid at `alpha`, fading to 0 over `blur` pixels outside it (a distance
    /// falloff). `blur <= 0` is the hard `shadowLayer`.
    func softShadowLayer(dx: Int, dy: Int, color: (r: UInt8, g: UInt8, b: UInt8),
                         alpha: UInt8, blur: Int, alphaThreshold: UInt8 = 128) -> RGBAImage {
        guard alpha > 0 else { return RGBAImage(width: width, height: height) }
        guard blur > 0 else {
            return shadowLayer(dx: dx, dy: dy, color: color, alpha: alpha, alphaThreshold: alphaThreshold)
        }
        let w = width, h = height
        let big = w + h + 1
        var dist = [Int](repeating: big, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let sx = x - dx, sy = y - dy
                if sx >= 0, sx < w, sy >= 0, sy < h, pixel(sx, sy).a >= alphaThreshold {
                    dist[y * w + x] = 0
                }
            }
        }
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            if x > 0 { dist[i] = min(dist[i], dist[i - 1] + 1) }
            if y > 0 { dist[i] = min(dist[i], dist[i - w] + 1) }
        } }
        for y in stride(from: h - 1, through: 0, by: -1) { for x in stride(from: w - 1, through: 0, by: -1) {
            let i = y * w + x
            if x < w - 1 { dist[i] = min(dist[i], dist[i + 1] + 1) }
            if y < h - 1 { dist[i] = min(dist[i], dist[i + w] + 1) }
        } }
        var out = RGBAImage(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let d = dist[y * w + x]
                let a: Double
                if d == 0 { a = Double(alpha) }
                else if d <= blur { a = Double(alpha) * Double(blur - d + 1) / Double(blur + 1) }
                else { continue }
                out.setPixel(x, y, color.r, color.g, color.b, u8(a))
            }
        }
        return out
    }

    /// Returns the image with an **outer** drop shadow behind it (silhouette
    /// offset by `(dx, dy)`, art composited back on top). Needs that much
    /// transparent margin on the offset side or the shadow is clipped.
    func droppingShadow(dx: Int, dy: Int, color: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 0),
                        alpha: UInt8 = 128, alphaThreshold: UInt8 = 128) -> RGBAImage {
        guard (dx != 0 || dy != 0), alpha > 0 else { return self }
        return shadowLayer(dx: dx, dy: dy, color: color, alpha: alpha, alphaThreshold: alphaThreshold)
            .blending(self, atX: 0, atY: 0)
    }

    /// Returns the image with an **inner** shadow: a recoloured band painted on
    /// top of the artwork along the inside edge facing `(-dx, -dy)` (where the
    /// shape, shifted by the offset, no longer covers itself). Stays within the
    /// silhouette, so it needs no margin.
    func innerShadow(dx: Int, dy: Int, color: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 0),
                     alpha: UInt8 = 128, blur: Int = 0, alphaThreshold: UInt8 = 128) -> RGBAImage {
        guard (dx != 0 || dy != 0), alpha > 0 else { return self }
        let w = width, h = height
        // The hard inner band: in-shape pixels whose back-shifted source is outside.
        var band = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                guard pixel(x, y).a >= alphaThreshold else { continue }
                let sx = x - dx, sy = y - dy
                let srcOpaque = sx >= 0 && sx < w && sy >= 0 && sy < h && pixel(sx, sy).a >= alphaThreshold
                if !srcOpaque { band[y * w + x] = true }
            }
        }
        var layer = RGBAImage(width: w, height: h)
        if blur <= 0 {
            for i in 0..<(w * h) where band[i] {
                layer.pixels[i * 4] = color.r; layer.pixels[i * 4 + 1] = color.g
                layer.pixels[i * 4 + 2] = color.b; layer.pixels[i * 4 + 3] = alpha
            }
        } else {
            let dist = Self.distanceTransform(band, width: w, height: h)
            for y in 0..<h {
                for x in 0..<w {
                    let i = y * w + x
                    guard pixel(x, y).a >= alphaThreshold else { continue } // clip to the shape
                    let d = dist[i]
                    let a: Double
                    if d == 0 { a = Double(alpha) }
                    else if d <= blur { a = Double(alpha) * Double(blur - d + 1) / Double(blur + 1) }
                    else { continue }
                    layer.setPixel(x, y, color.r, color.g, color.b, u8(a))
                }
            }
        }
        return blending(layer, atX: 0, atY: 0)
    }

    /// City-block distance from every pixel to the nearest `true` seed, via a
    /// two-pass approximate transform. Shared by the glow/outline/shadow effects.
    static func distanceTransform(_ seeds: [Bool], width w: Int, height h: Int) -> [Int] {
        let big = w + h + 1
        var dist = [Int](repeating: big, count: w * h)
        for i in 0..<(w * h) where seeds[i] { dist[i] = 0 }
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            if x > 0 { dist[i] = min(dist[i], dist[i - 1] + 1) }
            if y > 0 { dist[i] = min(dist[i], dist[i - w] + 1) }
        } }
        for y in stride(from: h - 1, through: 0, by: -1) { for x in stride(from: w - 1, through: 0, by: -1) {
            let i = y * w + x
            if x < w - 1 { dist[i] = min(dist[i], dist[i + 1] + 1) }
            if y < h - 1 { dist[i] = min(dist[i], dist[i + w] + 1) }
        } }
        return dist
    }

    /// Composites `top` over a copy of this image using source-over alpha
    /// blending, with `top`'s upper-left corner at `(atX, atY)`. Parts of `top`
    /// that fall outside the bounds are clipped. Used to stamp a badge/emblem
    /// onto icon artwork.
    func blending(_ top: RGBAImage, atX: Int, atY: Int) -> RGBAImage {
        var out = self
        for ty in 0..<top.height {
            let y = atY + ty
            guard y >= 0, y < height else { continue }
            for tx in 0..<top.width {
                let x = atX + tx
                guard x >= 0, x < width else { continue }
                let t = top.pixel(tx, ty)
                let ta = Double(t.a) / 255
                if ta <= 0 { continue }
                let b = pixel(x, y)
                let ba = Double(b.a) / 255
                let outA = ta + ba * (1 - ta)
                guard outA > 0 else { out.setPixel(x, y, 0, 0, 0, 0); continue }
                let r = (Double(t.r) * ta + Double(b.r) * ba * (1 - ta)) / outA
                let g = (Double(t.g) * ta + Double(b.g) * ba * (1 - ta)) / outA
                let bl = (Double(t.b) * ta + Double(b.b) * ba * (1 - ta)) / outA
                out.setPixel(x, y, u8(r), u8(g), u8(bl), u8(outA * 255))
            }
        }
        return out
    }
}

/// How `RGBAImage` scales source artwork into the icon canvas.
public enum ResampleFilter: String, Codable, CaseIterable, Equatable {
    case nearest // crisp; best for pixel art / upscaling
    case smooth  // area-average; best for shrinking photos
}

@inline(__always)
func u8(_ v: Double) -> UInt8 { UInt8(min(255, max(0, Int(v.rounded())))) }

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
