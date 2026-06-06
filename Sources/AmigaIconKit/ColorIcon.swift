import Foundation

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
    /// Use RLE (`ImageFormat`/`PaletteFormat` == 1). Uncompressed (`0`) is also
    /// a valid, simpler form and useful as a fallback when debugging.
    public var compress: Bool

    public init(normal: IndexedImage, selected: IndexedImage? = nil, compress: Bool = true) {
        self.normal = normal
        self.selected = selected
        self.compress = compress
    }

    /// Serialises the complete `FORM ICON` block.
    public func encode() -> [UInt8] {
        var body = BinaryWriter()
        body.ascii("ICON")

        // ---- FACE -------------------------------------------------------
        let maxColors = max(normal.colorCount, selected?.colorCount ?? 0)
        var face = BinaryWriter()
        face.u8(UInt8(min(255, normal.width - 1)))   // Width  - 1
        face.u8(UInt8(min(255, normal.height - 1)))  // Height - 1
        face.u8(0)                                    // Flags (bit0 = frameless); 0 = framed
        face.u8(0)                                    // Aspect (0 = unspecified)
        face.u16(UInt16(min(0xFFFF, maxColors * 3 - 1))) // MaxPaletteBytes - 1
        appendChunk(&body, id: "FACE", data: face.data)

        // ---- IMAG (normal) ---------------------------------------------
        appendChunk(&body, id: "IMAG", data: encodeImage(normal))

        // ---- IMAG (selected) -------------------------------------------
        if let sel = selected {
            appendChunk(&body, id: "IMAG", data: encodeImage(sel))
        }

        // ---- wrap in FORM ----------------------------------------------
        var form = BinaryWriter()
        form.ascii("FORM")
        form.u32(UInt32(body.data.count))
        form.bytes(body.data)
        return form.data
    }

    /// Encodes a single `IMAG` chunk body (header + image data + palette data).
    /// Each image carries its own palette here for maximum reader compatibility.
    private func encodeImage(_ img: IndexedImage) -> [UInt8] {
        let depth = img.depth
        let imageData = compress
            ? PackBits.packRLE(img.indices, itemBits: depth)
            : PackBits.packRaw(img.indices, itemBits: depth)

        // Palette: NumColors RGB triplets, optionally RLE'd (8-bit items).
        var paletteItems: [Int] = []
        paletteItems.reserveCapacity(img.palette.count * 3)
        for c in img.palette { paletteItems.append(Int(c.r)); paletteItems.append(Int(c.g)); paletteItems.append(Int(c.b)) }
        let paletteData = compress
            ? PackBits.packRLE(paletteItems, itemBits: 8)
            : PackBits.packRaw(paletteItems, itemBits: 8)

        var flags = 0
        if img.transparentIndex != nil { flags |= 0x01 } // bit0: has transparent colour
        flags |= 0x02                                      // bit1: has palette

        var w = BinaryWriter()
        w.u8(UInt8(img.transparentIndex ?? 0))            // TransparentColor
        w.u8(UInt8(min(255, img.colorCount - 1)))         // NumColors - 1
        w.u8(UInt8(flags))                                 // Flags
        w.u8(compress ? 1 : 0)                             // ImageFormat
        w.u8(compress ? 1 : 0)                             // PaletteFormat
        w.u8(UInt8(depth))                                 // Depth
        w.u16(UInt16(min(0xFFFF, imageData.count - 1)))    // NumImageBytes - 1
        w.u16(UInt16(min(0xFFFF, paletteData.count - 1)))  // NumPaletteBytes - 1
        w.bytes(imageData)
        w.bytes(paletteData)
        return w.data
    }

    /// Writes an IFF chunk (`id`, 32-bit length, data, even-padding byte).
    private func appendChunk(_ w: inout BinaryWriter, id: String, data: [UInt8]) {
        w.ascii(id)
        w.u32(UInt32(data.count))
        w.bytes(data)
        w.padEven()
    }
}
