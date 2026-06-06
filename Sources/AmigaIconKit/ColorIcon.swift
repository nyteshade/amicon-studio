import Foundation

/// Errors thrown when an image cannot be represented as an OS3.5+ ColorIcon.
/// These are hard limits of the on-disk format, not arbitrary choices: `FACE`
/// stores width/height as `UBYTE` (so each side is 1...256), `NumColors` is a
/// `UBYTE` (1...256), and the per-image `NumImageBytes`/`NumPaletteBytes` are
/// `UWORD` (so each packed stream is at most 65536 bytes). Exceeding any of
/// these used to be silently clamped — which produced a corrupt icon — and now
/// fails loudly instead.
public enum ColorIconError: Error, Equatable {
    case dimensionTooLarge(width: Int, height: Int) // each side must be 1...256
    case tooManyColors(Int)                          // palette must be 1...256
    case imageDataTooLarge(bytes: Int)               // packed image stream > 65536
    case paletteDataTooLarge(bytes: Int)             // packed palette stream > 65536
}

/// Builds the OS3.5+ **ColorIcon** ("GlowIcon") payload: an IFF `FORM ICON`
/// containing a `FACE` chunk and one or two `IMAG` chunks. This block is
/// appended verbatim to the end of a classic `.info` file; icon.library on
/// OS3.5+ reads it in preference to the planar image, while older systems
/// ignore the trailing data and fall back to the planar `Image`.
///
/// Palettes are full 24-bit RGB (up to 256 entries) — this is the format meant
/// by "24-bit RGB icons supported by AmigaOS 3.2+". Pixels are palette indices,
/// bit-packed at the image `Depth` and (by default) RLE-compressed.
public struct ColorIcon {
    public var normal: IndexedImage
    public var selected: IndexedImage?
    /// Prefer RLE (`ImageFormat`/`PaletteFormat` == 1) when it is actually
    /// smaller than the raw packing. Set `false` to force the uncompressed form,
    /// which is simpler and useful when debugging.
    public var compress: Bool

    public init(normal: IndexedImage, selected: IndexedImage? = nil, compress: Bool = true) {
        self.normal = normal
        self.selected = selected
        self.compress = compress
    }

    /// Largest value the format's 16-bit `Num*Bytes` field can express: the field
    /// stores `(count - 1)`, so a packed stream may be up to 65536 bytes.
    public static let maxStreamBytes = 65536
    /// `FACE` width/height and `NumColors` store `(value - 1)` in a byte.
    public static let maxDimension = 256
    public static let maxColors = 256

    /// Serialises the complete `FORM ICON` block.
    public func encode() throws -> [UInt8] {
        try validate(normal)
        if let sel = selected { try validate(sel) }

        var body = BinaryWriter()
        body.ascii("ICON")

        // ---- FACE -------------------------------------------------------
        let maxColors = max(normal.colorCount, selected?.colorCount ?? 0)
        var face = BinaryWriter()
        face.u8(UInt8(normal.width - 1))    // Width  - 1  (validated 1...256)
        face.u8(UInt8(normal.height - 1))   // Height - 1
        face.u8(0)                          // Flags (bit0 = frameless); 0 = framed
        face.u8(0)                          // Aspect (0 = unspecified)
        face.u16(UInt16(maxColors * 3 - 1)) // MaxPaletteBytes - 1 (<= 767, fits)
        appendChunk(&body, id: "FACE", data: face.data)

        // ---- IMAG (normal, then optional selected) ---------------------
        appendChunk(&body, id: "IMAG", data: try encodeImage(normal))
        if let sel = selected {
            appendChunk(&body, id: "IMAG", data: try encodeImage(sel))
        }

        // ---- wrap in FORM ----------------------------------------------
        var form = BinaryWriter()
        form.ascii("FORM")
        form.u32(UInt32(body.data.count))
        form.bytes(body.data)
        return form.data
    }

    private func validate(_ img: IndexedImage) throws {
        guard (1...ColorIcon.maxDimension).contains(img.width),
              (1...ColorIcon.maxDimension).contains(img.height) else {
            throw ColorIconError.dimensionTooLarge(width: img.width, height: img.height)
        }
        guard (1...ColorIcon.maxColors).contains(img.colorCount) else {
            throw ColorIconError.tooManyColors(img.colorCount)
        }
    }

    /// Encodes a single `IMAG` chunk body (header + image data + palette data).
    /// Each image carries its own palette here for maximum reader compatibility.
    private func encodeImage(_ img: IndexedImage) throws -> [UInt8] {
        let depth = img.depth

        // Pick the smaller of the RLE and raw packings for each stream. RLE can
        // *expand* noisy data, so always choosing it (the old behaviour) both
        // wasted space and risked overflowing the 16-bit length field. The raw
        // packing of any in-range image is <= 65536 bytes, so taking the smaller
        // keeps every in-range icon representable.
        let (imageData, imageFormat) = bestStream(img.indices, itemBits: depth)

        var paletteItems: [Int] = []
        paletteItems.reserveCapacity(img.palette.count * 3)
        for c in img.palette {
            paletteItems.append(Int(c.r)); paletteItems.append(Int(c.g)); paletteItems.append(Int(c.b))
        }
        let (paletteData, paletteFormat) = bestStream(paletteItems, itemBits: 8)

        guard imageData.count <= ColorIcon.maxStreamBytes else {
            throw ColorIconError.imageDataTooLarge(bytes: imageData.count)
        }
        guard paletteData.count <= ColorIcon.maxStreamBytes else {
            throw ColorIconError.paletteDataTooLarge(bytes: paletteData.count)
        }

        var flags = 0
        if img.transparentIndex != nil { flags |= 0x01 } // bit0: has transparent colour
        flags |= 0x02                                      // bit1: has palette

        var w = BinaryWriter()
        w.u8(UInt8(img.transparentIndex ?? 0))            // TransparentColor
        w.u8(UInt8(img.colorCount - 1))                    // NumColors - 1 (validated)
        w.u8(UInt8(flags))                                 // Flags
        w.u8(imageFormat)                                  // ImageFormat (0 raw / 1 RLE)
        w.u8(paletteFormat)                                // PaletteFormat
        w.u8(UInt8(depth))                                 // Depth
        w.u16(UInt16(imageData.count - 1))                 // NumImageBytes - 1
        w.u16(UInt16(paletteData.count - 1))               // NumPaletteBytes - 1
        w.bytes(imageData)
        w.bytes(paletteData)
        return w.data
    }

    /// Returns the smaller of the RLE and raw bit-packings of `items`, with the
    /// matching `ImageFormat`/`PaletteFormat` code (1 = RLE, 0 = raw). When
    /// `compress` is off, always returns the raw packing.
    private func bestStream(_ items: [Int], itemBits: Int) -> (data: [UInt8], format: UInt8) {
        let raw = PackBits.packRaw(items, itemBits: itemBits)
        guard compress else { return (raw, 0) }
        let rle = PackBits.packRLE(items, itemBits: itemBits)
        return rle.count < raw.count ? (rle, 1) : (raw, 0)
    }

    /// Writes an IFF chunk (`id`, 32-bit length, data, even-padding byte).
    private func appendChunk(_ w: inout BinaryWriter, id: String, data: [UInt8]) {
        w.ascii(id)
        w.u32(UInt32(data.count))
        w.bytes(data)
        w.padEven()
    }
}
