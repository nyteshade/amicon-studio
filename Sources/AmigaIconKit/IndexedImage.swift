import Foundation

/// An RGB colour, 8 bits per component, as stored in an Amiga icon palette.
/// (ColorIcon palettes are full 24-bit RGB — this is where "24-bit RGB icons"
/// comes from; the image itself is still palette-indexed, up to 256 entries.)
public struct RGB: Equatable, Hashable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

/// A palette-indexed image: one byte (index into `palette`) per pixel, plus an
/// optional transparent colour index.
public struct IndexedImage {
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
    public static func map(_ image: RGBAImage,
                           to palette: [RGB],
                           backgroundIndex: Int = 0,
                           alphaThreshold: UInt8 = 128) -> IndexedImage {
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
