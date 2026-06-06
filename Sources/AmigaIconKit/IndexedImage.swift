import Foundation

/// An RGB colour, 8 bits per component, as stored in an Amiga icon palette.
/// (ColorIcon palettes are full 24-bit RGB — this is where "24-bit RGB icons"
/// comes from; the image itself is still palette-indexed, up to 256 entries.)
public struct RGB: Equatable, Hashable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

/// Error-diffusion mode used when reducing an image to a fixed palette.
public enum DitherMode: String, Codable, CaseIterable, Equatable {
    case none           // snap each pixel to its nearest pen
    case floydSteinberg // diffuse quantisation error to neighbours
}

/// A palette-indexed image: one byte (index into `palette`) per pixel, plus an
/// optional transparent colour index.
public struct IndexedImage: Equatable {
    public let width: Int
    public let height: Int
    public var indices: [Int]      // width * height, each an index into palette
    public var palette: [RGB]
    /// Index of the transparent colour, or `nil` if the image is fully opaque.
    public var transparentIndex: Int?

    public var colorCount: Int { palette.count }
    /// Bits required to represent every palette index.
    public var depth: Int { max(1, Int(ceil(log2(Double(max(2, palette.count)))))) }
}

public extension IndexedImage {
    /// Renders the indexed image back to a straight RGBA buffer using its own
    /// palette. The `transparentIndex`, if any, is emitted as fully transparent
    /// (alpha 0); every other index uses its palette colour at full opacity.
    ///
    /// This is the inverse of quantisation and the basis of an accurate
    /// "what the Amiga actually shows" preview: it reflects the real, reduced
    /// palette rather than the original full-colour source.
    func rgba() -> RGBAImage {
        var out = RGBAImage(width: width, height: height)
        for i in 0 ..< (width * height) {
            let idx = indices[i]
            if idx == transparentIndex { continue } // leave fully transparent
            let c = (idx >= 0 && idx < palette.count) ? palette[idx] : RGB(0, 0, 0)
            let p = i * 4
            out.pixels[p] = c.r; out.pixels[p + 1] = c.g; out.pixels[p + 2] = c.b; out.pixels[p + 3] = 255
        }
        return out
    }
}

/// Reduces an `RGBAImage` to a palette of at most `maxColors` entries using a
/// median-cut quantiser. Transparent pixels (alpha below `alphaThreshold`) are
/// collapsed onto a single dedicated palette entry, exposed as
/// `transparentIndex` — this is how ColorIcons encode transparency.
public enum ColorQuantizer {

    public static func quantize(_ image: RGBAImage,
                                maxColors: Int = 256,
                                alphaThreshold: UInt8 = 128) -> IndexedImage {
        precondition(maxColors >= 2 && maxColors <= 256)
        let w = image.width, h = image.height

        // Partition pixels into transparent vs opaque.
        var opaque: [RGB] = []
        opaque.reserveCapacity(w * h)
        var isTransparent = [Bool](repeating: false, count: w * h)
        var anyTransparent = false
        for i in 0..<(w * h) {
            let a = image.pixels[i * 4 + 3]
            if a < alphaThreshold {
                isTransparent[i] = true
                anyTransparent = true
            } else {
                opaque.append(RGB(image.pixels[i * 4],
                                  image.pixels[i * 4 + 1],
                                  image.pixels[i * 4 + 2]))
            }
        }

        // Reserve one slot for the transparent colour if needed.
        let colorBudget = anyTransparent ? maxColors - 1 : maxColors
        let palette = medianCut(opaque, maxColors: max(1, colorBudget))

        // Map every opaque pixel to its nearest palette entry.
        var indices = [Int](repeating: 0, count: w * h)
        var cache: [RGB: Int] = [:]
        var finalPalette = palette
        let transparentIndex: Int?
        if anyTransparent {
            transparentIndex = finalPalette.count
            finalPalette.append(RGB(0, 0, 0)) // value is irrelevant; it is transparent
        } else {
            transparentIndex = nil
        }

        for i in 0..<(w * h) {
            if isTransparent[i] {
                indices[i] = transparentIndex ?? 0
                continue
            }
            let c = RGB(image.pixels[i * 4], image.pixels[i * 4 + 1], image.pixels[i * 4 + 2])
            if let hit = cache[c] {
                indices[i] = hit
            } else {
                let idx = nearest(c, in: palette)
                cache[c] = idx
                indices[i] = idx
            }
        }

        return IndexedImage(width: w, height: h, indices: indices,
                            palette: finalPalette, transparentIndex: transparentIndex)
    }

    /// Maps an image onto a *fixed* palette (used by the classic planar writer,
    /// which must use the Workbench screen palette rather than its own).
    /// `dither` controls error diffusion: `.none` snaps each pixel to its nearest
    /// pen, `.floydSteinberg` diffuses the quantisation error to neighbours,
    /// which greatly improves how photos read at 4–16 pens.
    public static func map(_ image: RGBAImage,
                           to palette: [RGB],
                           backgroundIndex: Int = 0,
                           alphaThreshold: UInt8 = 128,
                           dither: DitherMode = .none) -> IndexedImage {
        switch dither {
        case .none:
            return mapNearest(image, to: palette, backgroundIndex: backgroundIndex, alphaThreshold: alphaThreshold)
        case .floydSteinberg:
            return mapFloydSteinberg(image, to: palette, backgroundIndex: backgroundIndex, alphaThreshold: alphaThreshold)
        }
    }

    private static func mapNearest(_ image: RGBAImage, to palette: [RGB],
                                   backgroundIndex: Int, alphaThreshold: UInt8) -> IndexedImage {
        let w = image.width, h = image.height
        var indices = [Int](repeating: 0, count: w * h)
        var cache: [RGB: Int] = [:]
        for i in 0..<(w * h) {
            if image.pixels[i * 4 + 3] < alphaThreshold {
                indices[i] = backgroundIndex
                continue
            }
            let c = RGB(image.pixels[i * 4], image.pixels[i * 4 + 1], image.pixels[i * 4 + 2])
            if let hit = cache[c] { indices[i] = hit }
            else { let idx = nearest(c, in: palette); cache[c] = idx; indices[i] = idx }
        }
        return IndexedImage(width: w, height: h, indices: indices,
                            palette: palette, transparentIndex: nil)
    }

    private static func mapFloydSteinberg(_ image: RGBAImage, to palette: [RGB],
                                          backgroundIndex: Int, alphaThreshold: UInt8) -> IndexedImage {
        let w = image.width, h = image.height
        var indices = [Int](repeating: 0, count: w * h)
        // Floating RGB working buffer that accumulates diffused error.
        var buf = [Double](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            buf[i * 3] = Double(image.pixels[i * 4])
            buf[i * 3 + 1] = Double(image.pixels[i * 4 + 1])
            buf[i * 3 + 2] = Double(image.pixels[i * 4 + 2])
        }
        // Push the quantisation error into a still-unprocessed, opaque neighbour.
        func diffuse(_ nx: Int, _ ny: Int, _ er: Double, _ eg: Double, _ eb: Double, _ f: Double) {
            guard nx >= 0, nx < w, ny >= 0, ny < h else { return }
            let j = ny * w + nx
            guard image.pixels[j * 4 + 3] >= alphaThreshold else { return }
            buf[j * 3] += er * f; buf[j * 3 + 1] += eg * f; buf[j * 3 + 2] += eb * f
        }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if image.pixels[i * 4 + 3] < alphaThreshold { indices[i] = backgroundIndex; continue }
                let c = RGB(u8(buf[i * 3]), u8(buf[i * 3 + 1]), u8(buf[i * 3 + 2]))
                let idx = nearest(c, in: palette)
                indices[i] = idx
                let p = palette[idx]
                let er = buf[i * 3] - Double(p.r)
                let eg = buf[i * 3 + 1] - Double(p.g)
                let eb = buf[i * 3 + 2] - Double(p.b)
                diffuse(x + 1, y,     er, eg, eb, 7.0 / 16)
                diffuse(x - 1, y + 1, er, eg, eb, 3.0 / 16)
                diffuse(x,     y + 1, er, eg, eb, 5.0 / 16)
                diffuse(x + 1, y + 1, er, eg, eb, 1.0 / 16)
            }
        }
        return IndexedImage(width: w, height: h, indices: indices,
                            palette: palette, transparentIndex: nil)
    }

    /// Maps an image onto a palette whose first `reserved.count` entries are the
    /// **fixed Workbench system pens** and whose remaining entries (up to
    /// `totalColors`) are generated from the image's own colours by median cut.
    /// Every pixel is then matched to the nearest entry of the combined palette;
    /// transparent pixels collapse to `backgroundIndex` (pen 0, the Workbench
    /// background).
    ///
    /// This is how well-behaved 8/16-colour Amiga icons reduce colour: they never
    /// clobber the reserved desktop pens, but can still introduce their own
    /// colours in the pens above them.
    public static func mapReserving(_ image: RGBAImage,
                                    reserved: [RGB],
                                    totalColors: Int,
                                    backgroundIndex: Int = 0,
                                    alphaThreshold: UInt8 = 128,
                                    dither: DitherMode = .none) -> IndexedImage {
        let freeBudget = max(0, totalColors - reserved.count)
        var freeColors: [RGB] = []
        if freeBudget > 0 {
            let w = image.width, h = image.height
            var opaque: [RGB] = []
            opaque.reserveCapacity(w * h)
            for i in 0 ..< (w * h) where image.pixels[i * 4 + 3] >= alphaThreshold {
                opaque.append(RGB(image.pixels[i * 4], image.pixels[i * 4 + 1], image.pixels[i * 4 + 2]))
            }
            if !opaque.isEmpty { freeColors = medianCut(opaque, maxColors: freeBudget) }
        }
        return map(image, to: reserved + freeColors,
                   backgroundIndex: backgroundIndex, alphaThreshold: alphaThreshold, dither: dither)
    }

    // MARK: - Median cut

    private static func medianCut(_ colors: [RGB], maxColors: Int) -> [RGB] {
        if colors.isEmpty { return [RGB(0, 0, 0)] }
        var boxes: [[RGB]] = [colors]
        while boxes.count < maxColors {
            // Find the box with the largest colour range on any axis.
            guard let (bi, axis) = widestBox(boxes) else { break }
            var box = boxes[bi]
            box.sort { component($0, axis) < component($1, axis) }
            let mid = box.count / 2
            guard mid > 0 && mid < box.count else { break }
            boxes[bi] = Array(box[0..<mid])
            boxes.append(Array(box[mid...]))
        }
        return boxes.map { averageColor($0) }
    }

    private static func widestBox(_ boxes: [[RGB]]) -> (Int, Int)? {
        var bestBox = -1, bestAxis = 0, bestRange = -1
        for (i, box) in boxes.enumerated() where box.count > 1 {
            for axis in 0..<3 {
                let vals = box.map { Int(component($0, axis)) }
                let range = (vals.max() ?? 0) - (vals.min() ?? 0)
                if range > bestRange { bestRange = range; bestBox = i; bestAxis = axis }
            }
        }
        return bestBox >= 0 ? (bestBox, bestAxis) : nil
    }

    private static func averageColor(_ box: [RGB]) -> RGB {
        guard !box.isEmpty else { return RGB(0, 0, 0) }
        var rs = 0, gs = 0, bs = 0
        for c in box { rs += Int(c.r); gs += Int(c.g); bs += Int(c.b) }
        let n = box.count
        return RGB(UInt8(rs / n), UInt8(gs / n), UInt8(bs / n))
    }

    @inline(__always)
    private static func component(_ c: RGB, _ axis: Int) -> UInt8 {
        axis == 0 ? c.r : (axis == 1 ? c.g : c.b)
    }

    static func nearest(_ c: RGB, in palette: [RGB]) -> Int {
        var best = 0, bestDist = Int.max
        for (i, p) in palette.enumerated() {
            let dr = Int(c.r) - Int(p.r)
            let dg = Int(c.g) - Int(p.g)
            let db = Int(c.b) - Int(p.b)
            let d = dr * dr + dg * dg + db * db
            if d < bestDist { bestDist = d; best = i; if d == 0 { break } }
        }
        return best
    }
}
