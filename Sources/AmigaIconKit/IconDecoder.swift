import Foundation

/// Reads an Amiga `.info` file back into structured data — the inverse of
/// `IconWriter`. It parses the `DiskObject`/`Gadget` header, the classic planar
/// `Image`(s), the `DefaultTool`/`ToolTypes` strings, and any trailing
/// `FORM ICON` (OS3.5+ GlowIcon / ColorIcon).
///
/// The decoder exists primarily to (a) prove round-trip correctness in tests —
/// the encoder's bytes must decode back to the same pixels — and (b) power an
/// accurate preview that shows the real, palette-reduced result rather than the
/// full-colour source. It is pure Foundation, so it builds and tests on Linux.
public enum IconDecoder {

    public enum DecodeError: Error, Equatable {
        case badMagic(UInt16)
        case missingGadgetImage
        case malformedColorIcon(String)
    }

    /// A decoded classic planar image. The `.info` format stores no palette of
    /// its own for the planar image — the raw `indices` are interpreted against
    /// the live Workbench screen palette — so rendering requires a palette to be
    /// supplied (see `rgba(palette:transparentIndex:)`).
    public struct PlanarImageData: Equatable {
        public let width: Int
        public let height: Int
        public let depth: Int
        public let indices: [Int] // width * height

        /// Wraps the indices in an `IndexedImage` against the supplied palette.
        public func indexed(palette: [RGB], transparentIndex: Int? = nil) -> IndexedImage {
            IndexedImage(width: width, height: height, indices: indices,
                         palette: palette, transparentIndex: transparentIndex)
        }

        /// Renders to RGBA using the supplied palette. `transparentIndex`
        /// (commonly `0`, the Workbench background) is drawn transparent so the
        /// icon reads against a checkerboard the way it does on the Workbench.
        public func rgba(palette: [RGB], transparentIndex: Int? = nil) -> RGBAImage {
            indexed(palette: palette, transparentIndex: transparentIndex).rgba()
        }
    }

    /// The fully decoded contents of an `.info` file.
    public struct DecodedIcon {
        public var rawType: UInt8
        public var type: IconType?
        public var gadgetWidth: Int
        public var gadgetHeight: Int
        public var defaultTool: String?
        public var toolTypes: [String]
        /// Window record for disk/drawer icons, if present.
        public var drawer: DrawerInfo?
        public var planarNormal: PlanarImageData
        public var planarSelected: PlanarImageData?
        /// Decoded GlowIcon normal/selected states (each carries its own palette
        /// and transparent index), present only when the file has a `FORM ICON`.
        public var colorIconNormal: IndexedImage?
        public var colorIconSelected: IndexedImage?

        public var hasColorIcon: Bool { colorIconNormal != nil }
    }

    // MARK: - Top-level

    public static func decode(_ data: [UInt8]) throws -> DecodedIcon {
        var r = BinaryReader(data)

        // ---- DiskObject header -----------------------------------------
        let magic = try r.u16()
        guard magic == 0xE310 else { throw DecodeError.badMagic(magic) }
        _ = try r.u16() // do_Version

        // struct Gadget (44 bytes)
        _ = try r.u32()                      // ga_NextGadget
        _ = try r.i16()                      // ga_LeftEdge
        _ = try r.i16()                      // ga_TopEdge
        let gWidth = Int(try r.i16())        // ga_Width
        let gHeight = Int(try r.i16())       // ga_Height
        _ = try r.u16()                      // ga_Flags
        _ = try r.u16()                      // ga_Activation
        _ = try r.u16()                      // ga_GadgetType
        let gadgetRender = try r.u32()       // ga_GadgetRender (non-zero: image follows)
        let selectRender = try r.u32()       // ga_SelectRender (non-zero: 2nd image)
        _ = try r.u32()                      // ga_GadgetText
        _ = try r.i32()                      // ga_MutualExclude
        _ = try r.u32()                      // ga_SpecialInfo
        _ = try r.u16()                      // ga_GadgetID
        _ = try r.u32()                      // ga_UserData

        let rawType = try r.u8()             // do_Type
        _ = try r.u8()                       // padding
        let hasDefaultTool = try r.u32() != 0 // do_DefaultTool pointer
        let hasToolTypes = try r.u32() != 0   // do_ToolTypes pointer
        _ = try r.i32()                      // do_CurrentX
        _ = try r.i32()                      // do_CurrentY
        let drawerDataPtr = try r.u32()      // do_DrawerData
        _ = try r.u32()                      // do_ToolWindow
        _ = try r.i32()                      // do_StackSize

        // DrawerData (disk/drawer icons): a 56-byte record before the images.
        var drawer: DrawerInfo?
        if drawerDataPtr != 0 { drawer = try readDrawerData(&r) }

        // ---- Images ----------------------------------------------------
        guard gadgetRender != 0 else { throw DecodeError.missingGadgetImage }
        let planarNormal = try decodeImage(&r)
        var planarSelected: PlanarImageData?
        if selectRender != 0 { planarSelected = try decodeImage(&r) }

        // ---- DefaultTool / ToolTypes -----------------------------------
        var defaultTool: String?
        if hasDefaultTool { defaultTool = try readSizedString(&r) }

        var toolTypes: [String] = []
        if hasToolTypes {
            // On disk: a 32-bit field equal to (n + 1) * 4, then n sized strings.
            let field = Int(try r.u32())
            let count = max(0, field / 4 - 1)
            toolTypes.reserveCapacity(count)
            for _ in 0 ..< count { toolTypes.append(try readSizedString(&r)) }
        }

        // ---- Trailing ColorIcon (GlowIcon) -----------------------------
        var colorNormal: IndexedImage?
        var colorSelected: IndexedImage?
        if r.peekAscii(4) == "FORM" {
            let imgs = try decodeColorIconForm(&r)
            colorNormal = imgs.normal
            colorSelected = imgs.selected
        }

        return DecodedIcon(rawType: rawType,
                           type: IconType(rawValue: rawType),
                           gadgetWidth: gWidth,
                           gadgetHeight: gHeight,
                           defaultTool: defaultTool,
                           toolTypes: toolTypes,
                           drawer: drawer,
                           planarNormal: planarNormal,
                           planarSelected: planarSelected,
                           colorIconNormal: colorNormal,
                           colorIconSelected: colorSelected)
    }

    /// Decodes a standalone IFF `FORM ICON` block (the GlowIcon payload).
    /// Useful on its own for validating the ColorIcon encoder.
    public static func decodeColorIconForm(_ bytes: [UInt8])
        throws -> (normal: IndexedImage?, selected: IndexedImage?) {
        var r = BinaryReader(bytes)
        return try decodeColorIconForm(&r)
    }

    /// Decodes a single classic `Image` block (20-byte header + planes).
    public static func decodeImageBlock(_ bytes: [UInt8]) throws -> PlanarImageData {
        var r = BinaryReader(bytes)
        return try decodeImage(&r)
    }

    // MARK: - Planar Image

    private static func decodeImage(_ r: inout BinaryReader) throws -> PlanarImageData {
        _ = try r.i16()                  // LeftEdge
        _ = try r.i16()                  // TopEdge
        let width = Int(try r.i16())     // Width
        let height = Int(try r.i16())    // Height
        let depth = Int(try r.i16())     // Depth
        _ = try r.u32()                  // ImageData pointer marker
        _ = try r.u8()                   // PlanePick
        _ = try r.u8()                   // PlaneOnOff
        _ = try r.u32()                  // NextImage

        let rb = ((width + 15) / 16) * 2 // word-aligned bytes per row, per plane
        let planeData = try r.bytes(rb * height * depth)

        var indices = [Int](repeating: 0, count: max(0, width * height))
        for plane in 0 ..< depth {
            let planeBase = plane * rb * height
            for y in 0 ..< height {
                let rowBase = planeBase + y * rb
                for x in 0 ..< width {
                    let bit = (Int(planeData[rowBase + (x >> 3)]) >> (7 - (x & 7))) & 1
                    if bit != 0 { indices[y * width + x] |= (1 << plane) }
                }
            }
        }
        return PlanarImageData(width: width, height: height, depth: depth, indices: indices)
    }

    // MARK: - ColorIcon FORM ICON

    private static func decodeColorIconForm(_ r: inout BinaryReader)
        throws -> (normal: IndexedImage?, selected: IndexedImage?) {
        let formId = try r.ascii(4)
        guard formId == "FORM" else { throw DecodeError.malformedColorIcon("expected FORM, got \(formId)") }
        let formSize = Int(try r.u32())
        let formEnd = min(r.data.count, r.offset + formSize)
        let typeId = try r.ascii(4)
        guard typeId == "ICON" else { throw DecodeError.malformedColorIcon("expected ICON, got \(typeId)") }

        var faceWidth = 0, faceHeight = 0
        var images: [IndexedImage] = []

        while r.offset + 8 <= formEnd {
            let chunkId = try r.ascii(4)
            let chunkSize = Int(try r.u32())
            let chunkStart = r.offset
            switch chunkId {
            case "FACE":
                faceWidth = Int(try r.u8()) + 1   // Width  - 1
                faceHeight = Int(try r.u8()) + 1  // Height - 1
                // remaining FACE fields (flags, aspect, maxPaletteBytes) unused here
            case "IMAG":
                images.append(try decodeImag(&r, width: faceWidth, height: faceHeight))
            default:
                break // skip unknown chunks
            }
            // Advance to the next chunk: chunk body is even-padded.
            var next = chunkStart + chunkSize
            if chunkSize % 2 != 0 { next += 1 }
            try r.seek(to: min(next, r.data.count))
        }

        return (images.first, images.count > 1 ? images[1] : nil)
    }

    private static func decodeImag(_ r: inout BinaryReader,
                                   width: Int, height: Int) throws -> IndexedImage {
        let transparentColor = Int(try r.u8()) // TransparentColor
        let numColors = Int(try r.u8()) + 1    // NumColors - 1
        let flags = try r.u8()                 // Flags
        let imageFormat = try r.u8()           // 0 = raw, 1 = RLE
        let paletteFormat = try r.u8()         // 0 = raw, 1 = RLE
        let depth = Int(try r.u8())            // Depth
        let numImageBytes = Int(try r.u16()) + 1
        let numPaletteBytes = Int(try r.u16()) + 1

        let imageData = try r.bytes(numImageBytes)
        let paletteData = try r.bytes(numPaletteBytes)

        let pixelCount = max(0, width * height)
        let indices = imageFormat == 1
            ? PackBits.unpackRLE(imageData, itemBits: depth, count: pixelCount)
            : PackBits.unpackRaw(imageData, itemBits: depth, count: pixelCount)

        let paletteItems = paletteFormat == 1
            ? PackBits.unpackRLE(paletteData, itemBits: 8, count: numColors * 3)
            : PackBits.unpackRaw(paletteData, itemBits: 8, count: numColors * 3)

        var palette: [RGB] = []
        palette.reserveCapacity(numColors)
        for i in 0 ..< numColors {
            palette.append(RGB(UInt8(paletteItems[i * 3] & 0xFF),
                               UInt8(paletteItems[i * 3 + 1] & 0xFF),
                               UInt8(paletteItems[i * 3 + 2] & 0xFF)))
        }

        let hasTransparency = (flags & 0x01) != 0
        return IndexedImage(width: width, height: height, indices: indices,
                            palette: palette,
                            transparentIndex: hasTransparency ? transparentColor : nil)
    }

    // MARK: - DrawerData

    private static func readDrawerData(_ r: inout BinaryReader) throws -> DrawerInfo {
        let left = try r.i16(), top = try r.i16(), width = try r.i16(), height = try r.i16()
        _ = try r.u8(); _ = try r.u8()        // DetailPen, BlockPen
        _ = try r.u32()                        // IDCMPFlags
        _ = try r.u32()                        // Flags
        _ = try r.u32()                        // FirstGadget
        _ = try r.u32()                        // CheckMark
        _ = try r.u32()                        // Title
        _ = try r.u32()                        // Screen
        _ = try r.u32()                        // BitMap
        _ = try r.i16(); _ = try r.i16()      // MinWidth, MinHeight
        _ = try r.u16(); _ = try r.u16()      // MaxWidth, MaxHeight
        _ = try r.u16()                        // Type
        let cx = try r.i32(), cy = try r.i32()
        return DrawerInfo(left: left, top: top, width: width, height: height,
                          currentX: cx, currentY: cy)
    }

    // MARK: - Strings

    /// Reads an Amiga sized string: 32-bit length (including the trailing NUL),
    /// then that many bytes (Latin-1), the last of which is the NUL.
    private static func readSizedString(_ r: inout BinaryReader) throws -> String {
        let size = Int(try r.u32())
        guard size >= 1 else { return "" }
        let raw = try r.bytes(size)
        let content = raw.prefix(size - 1) // drop trailing NUL
        // Latin-1: each byte maps directly to the matching Unicode scalar.
        return String(String.UnicodeScalarView(content.map { Unicode.Scalar($0) }))
    }
}

public extension IconDecoder.DecodedIcon {
    /// Best full-colour rendering of the **normal** state for re-editing an
    /// existing icon: the GlowIcon if the file has one, otherwise the classic
    /// planar image rendered against `planarPalette` (pen 0 shown transparent).
    func renderedNormal(planarPalette: [RGB] = magicWB8Palette) -> RGBAImage {
        colorIconNormal?.rgba() ?? planarNormal.rgba(palette: planarPalette, transparentIndex: 0)
    }

    /// Best full-colour rendering of the **clicked/selected** state, or `nil` if
    /// the file carries only a single (normal) image.
    func renderedSelected(planarPalette: [RGB] = magicWB8Palette) -> RGBAImage? {
        if let c = colorIconSelected { return c.rgba() }
        return planarSelected?.rgba(palette: planarPalette, transparentIndex: 0)
    }

    /// A short human-readable summary of the icon's structure, used by
    /// `amigaicon inspect` and handy for debugging.
    var summary: String {
        var lines: [String] = []
        let typeName = type.map { "\($0)" } ?? "unknown(\(rawType))"
        lines.append("type:        \(typeName)")
        lines.append("gadget:      \(gadgetWidth)×\(gadgetHeight)")
        lines.append("planar:      \(planarNormal.width)×\(planarNormal.height), depth \(planarNormal.depth)"
                     + (planarSelected != nil ? " (+ selected)" : ""))
        if let n = colorIconNormal {
            lines.append("glowIcon:    \(n.width)×\(n.height), \(n.colorCount) colours"
                         + (n.transparentIndex != nil ? ", transparent" : "")
                         + (colorIconSelected != nil ? " (+ selected)" : ""))
        } else {
            lines.append("glowIcon:    none")
        }
        if let d = drawer {
            lines.append("drawer:      window \(d.width)×\(d.height) at (\(d.left),\(d.top))")
        }
        if let dt = defaultTool, !dt.isEmpty { lines.append("defaultTool: \(dt)") }
        if !toolTypes.isEmpty {
            lines.append("toolTypes:   \(toolTypes.count)")
            for tt in toolTypes { lines.append("  • \(tt)") }
        }
        return lines.joined(separator: "\n")
    }
}
