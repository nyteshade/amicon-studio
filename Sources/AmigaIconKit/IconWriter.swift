import Foundation

/// Options controlling how source artwork is turned into an Amiga `.info` file.
///
/// Defaults reflect typical conventions: a compact, few-colour **planar** image
/// for OS1–3 compatibility, plus a 24-bit **GlowIcon** (48×48 artwork centred in
/// a 54×54 canvas) for OS3.5+, with an auto-generated glow on the clicked state.
public struct IconOptions {
    public var type: IconType = .project
    public var defaultTool: String = ""
    public var toolTypes: [String] = []
    /// When set (typically for `.drawer`/`.disk` icons), a `DrawerData` window
    /// record is written so Workbench remembers the drawer window's position
    /// and size. `nil` for tool/project icons.
    public var drawerData: DrawerInfo? = nil

    // --- Classic planar fallback (always written; OS1–3 era) ---
    /// Which Workbench pen set the planar indices are matched against. Classic
    /// `.info` files store no palette of their own, so indices are interpreted
    /// against the live Workbench screen — matching the target release's pens is
    /// what makes the icon look right. The leading system pens are reserved; any
    /// pens above them are generated from the artwork during colour reduction.
    public var planarPalette: WorkbenchPalette = .workbench2_4
    /// On-disk planar image size (px). The Amiga has no fixed icon size; pick any
    /// width/height. `planarMargin` reserves room on every side for glow/outline/
    /// shadow.
    public var planarWidth: Int = 40
    public var planarHeight: Int = 40
    public var planarMargin: Int = 2

    // --- ColorIcon / GlowIcon (OS3.5+, 24-bit) ---
    public var writeColorIcon: Bool = true
    /// GlowIcon canvas size (px), up to 256×256 (the format's limit). Non-square
    /// is fine. `colorMargin` reserves room for glow/outline/shadow.
    public var colorWidth: Int = 54
    public var colorHeight: Int = 54
    public var colorMargin: Int = 3
    public var colorMaxColors: Int = 256
    public var compressColorIcon: Bool = true
    /// How artwork is scaled into the canvas content box (fit/fill/stretch).
    public var fitMode: FitMode = .fit

    // --- Selected ("clicked") state glow ---
    /// When no explicit selected image is supplied, derive the clicked state by
    /// adding a glow to the normal artwork.
    public var autoGlow: Bool = true
    /// Glow thickness in pixels. Clamped to the canvas margin so it never clips.
    public var glowRadius: Int = 3
    public var glowColor: RGB = RGB(0xFF, 0x8B, 0x00) // warm GlowIcon orange

    // --- Outline (solid stroke hugging the artwork) ---
    /// Outline thickness in pixels; `0` disables it. Drawn behind the art in the
    /// canvas margin (clamp to the margin to avoid clipping).
    public var outlineThickness: Int = 0
    public var outlineColor: RGB = RGB(0, 0, 0)

    // --- Shadows (any number, outer and/or inner), applied in order ---
    public var shadows: [Shadow] = []

    /// Posterize the artwork to this many levels per channel before reduction
    /// (`< 2` = off) for a banded/retro look.
    public var posterizeLevels: Int = 0

    // --- Orientation (applied to the source before fitting) ---
    public var flipHorizontal: Bool = false
    public var flipVertical: Bool = false
    public var rotateQuarters: Int = 0 // clockwise 90° turns

    /// Box-blur radius applied to the source before fitting (`0` = off).
    public var blurRadius: Int = 0

    /// Flat tint blended into the source (`tintAmount` 0 = off ... 1 = full).
    public var tintColor: RGB = RGB(0, 0, 0)
    public var tintAmount: Double = 0

    // --- NewIcons (experimental; off by default — see NewIcons.swift) ---
    public var writeNewIcons: Bool = false

    // --- Image quality ---
    /// Filter used when scaling source art into the icon canvas (`.smooth`
    /// area-averaging is best for shrinking photos; `.nearest` for pixel art).
    public var resampleFilter: ResampleFilter = .smooth
    /// Error-diffusion dithering for the low-colour planar reduction. On by
    /// default because it dramatically improves how photos read at 4–16 pens.
    public var planarDither: DitherMode = .floydSteinberg

    public init() {}
}

/// One shadow applied to the artwork — `outer` (offset silhouette behind the
/// art) or `inner` (recoloured band along the inside edge). Multiple shadows are
/// applied in order; outer shadows are all cast from the same artwork silhouette
/// so they don't stack on each other.
public struct Shadow: Equatable, Codable, Identifiable {
    public enum Kind: String, Codable, CaseIterable { case outer, inner }
    public var id = UUID()
    public var kind: Kind
    public var dx: Int
    public var dy: Int
    public var color: RGB
    public var alpha: UInt8
    /// Feathered edge width in pixels for **outer** shadows (0 = hard edge).
    public var blur: Int

    public init(kind: Kind = .outer, dx: Int = 2, dy: Int = 2,
                color: RGB = RGB(0, 0, 0), alpha: UInt8 = 128, blur: Int = 0) {
        self.kind = kind; self.dx = dx; self.dy = dy; self.color = color; self.alpha = alpha; self.blur = blur
    }
}

/// Assembles a complete `.info` file from source artwork.
public enum IconWriter {

    /// Builds the `.info` byte stream.
    ///
    /// - Parameters:
    ///   - normal: the unclicked-state artwork (any size; it is scaled/centred).
    ///   - selected: optional clicked-state artwork. If `nil` and `autoGlow` is
    ///               on, the clicked state is generated by glowing `normal`.
    public static func build(normal: RGBAImage,
                             selected: RGBAImage?,
                             options: IconOptions) throws -> [UInt8] {
        // ---- Planar fallback (Workbench pens; system pens reserved) -----
        let wb = options.planarPalette
        let planarNormal = planarIndexed(for: normal, options: options)
        let planarDepth = wb.depth
        let planarNormalImg = PlanarImage(planarNormal, depth: planarDepth)

        // A planar selected image is only written when the caller supplies one
        // explicitly (classic icons usually rely on colour-complement highlight).
        var planarSelectedImg: PlanarImage?
        if let sel = selected {
            let rgba = composed(sel, width: options.planarWidth, height: options.planarHeight,
                                margin: options.planarMargin, options: options)
            let mapped = ColorQuantizer.mapReserving(rgba, reserved: wb.systemPens,
                                                      totalColors: wb.totalColors,
                                                      dither: options.planarDither)
            planarSelectedImg = PlanarImage(mapped, depth: planarDepth)
        }

        // ---- ColorIcon / GlowIcon --------------------------------------
        var colorIcon: ColorIcon?
        if options.writeColorIcon {
            let normRGBA = composed(normal, width: options.colorWidth, height: options.colorHeight,
                                    margin: options.colorMargin, options: options)
            let normIndexed = ColorQuantizer.quantize(normRGBA, maxColors: options.colorMaxColors)

            let selRGBA: RGBAImage?
            if let sel = selected {
                selRGBA = composed(sel, width: options.colorWidth, height: options.colorHeight,
                                   margin: options.colorMargin, options: options)
            } else if options.autoGlow {
                // Glow may not exceed the margin, or it would be clipped.
                let margin = options.colorMargin
                let radius = max(1, min(options.glowRadius, max(1, margin)))
                selRGBA = normRGBA.addingGlow(radius: radius,
                                              color: (options.glowColor.r, options.glowColor.g, options.glowColor.b))
            } else {
                selRGBA = nil
            }
            let selIndexed = selRGBA.map { ColorQuantizer.quantize($0, maxColors: options.colorMaxColors) }
            colorIcon = ColorIcon(normal: normIndexed, selected: selIndexed,
                                  compress: options.compressColorIcon)
        }

        // ---- Tool types (optionally prefixed with NewIcons data) -------
        var toolTypes = options.toolTypes
        if options.writeNewIcons {
            let normIndexed = ColorQuantizer.quantize(
                composed(normal, width: options.colorWidth, height: options.colorHeight,
                         margin: options.colorMargin, options: options),
                maxColors: 256)
            let newIconLines = NewIcons.encode(normal: normIndexed, selected: nil)
            toolTypes = newIconLines + toolTypes
        }

        return try serialize(type: options.type,
                             defaultTool: options.defaultTool,
                             toolTypes: toolTypes,
                             drawer: options.drawerData,
                             planarNormal: planarNormalImg,
                             planarSelected: planarSelectedImg,
                             colorIcon: colorIcon)
    }

    /// The composed, pen-mapped planar image the writer embeds for the normal
    /// state. Exposed so a UI can preview the exact planar result (which pens the
    /// artwork reduced to) without re-deriving the pipeline.
    public static func planarIndexed(for normal: RGBAImage, options: IconOptions) -> IndexedImage {
        let wb = options.planarPalette
        let rgba = composed(normal, width: options.planarWidth, height: options.planarHeight,
                            margin: options.planarMargin, options: options)
        return ColorQuantizer.mapReserving(rgba, reserved: wb.systemPens, totalColors: wb.totalColors,
                                           dither: options.planarDither)
    }

    /// Orients, blurs/tints the source, fits it into a `width × height` canvas
    /// (with `margin`), then applies posterize / outline / shadows at final size.
    private static func composed(_ src: RGBAImage, width: Int, height: Int, margin: Int,
                                 options: IconOptions) -> RGBAImage {
        var source = (options.flipHorizontal || options.flipVertical || options.rotateQuarters % 4 != 0)
            ? src.oriented(flipH: options.flipHorizontal, flipV: options.flipVertical,
                           quarters: options.rotateQuarters)
            : src
        if options.blurRadius > 0 { source = source.boxBlurred(radius: options.blurRadius) }
        if options.tintAmount > 0 { source = source.tinted(color: options.tintColor, amount: options.tintAmount) }
        var img = source.fitted(width: width, height: height, margin: margin,
                                mode: options.fitMode, filter: options.resampleFilter)
        if options.posterizeLevels >= 2 { img = img.posterized(levels: options.posterizeLevels) }
        let room = max(1, margin) // breathing room for stroke/shadow at the edge
        if options.outlineThickness > 0 {
            img = img.outlined(color: (options.outlineColor.r, options.outlineColor.g, options.outlineColor.b),
                               thickness: min(options.outlineThickness, room))
        }
        if !options.shadows.isEmpty {
            img = applyShadows(options.shadows, to: img, margin: room)
        }
        return img
    }

    /// Applies all `shadows` to `img`: outer shadows are cast from the same
    /// silhouette and composited behind the art together (so they don't stack on
    /// one another), then inner shadows are painted on top in order. Outer
    /// offsets are clamped to `margin` so they aren't clipped.
    private static func applyShadows(_ shadows: [Shadow], to img: RGBAImage, margin: Int) -> RGBAImage {
        var out = img
        let outer = shadows.filter { $0.kind == .outer }
        if !outer.isEmpty {
            var bg = RGBAImage(width: img.width, height: img.height)
            for s in outer {
                let dx = clamp(s.dx, to: margin), dy = clamp(s.dy, to: margin)
                let layer = img.softShadowLayer(dx: dx, dy: dy,
                                                color: (s.color.r, s.color.g, s.color.b),
                                                alpha: s.alpha, blur: s.blur)
                bg = bg.blending(layer, atX: 0, atY: 0)
            }
            out = bg.blending(out, atX: 0, atY: 0) // art (+ inner later) over the shadows
        }
        for s in shadows where s.kind == .inner {
            out = out.innerShadow(dx: s.dx, dy: s.dy,
                                  color: (s.color.r, s.color.g, s.color.b), alpha: s.alpha, blur: s.blur)
        }
        return out
    }

    private static func clamp(_ v: Int, to margin: Int) -> Int { max(-margin, min(margin, v)) }

    /// Losslessly re-serialises a previously **decoded** icon back to `.info`
    /// bytes — useful for editing an existing icon's metadata (type, default
    /// tool, tool types, drawer window) or its already-reduced images without
    /// re-quantising any source artwork. Mutate the `DecodedIcon` fields first,
    /// then call this.
    public static func reencode(_ decoded: IconDecoder.DecodedIcon) throws -> [UInt8] {
        func planar(_ p: IconDecoder.PlanarImageData) -> PlanarImage {
            // PlanarImage only needs the indices + depth; the palette is unused.
            let placeholder = [RGB](repeating: RGB(0, 0, 0), count: max(2, 1 << p.depth))
            let idx = IndexedImage(width: p.width, height: p.height, indices: p.indices,
                                   palette: placeholder, transparentIndex: nil)
            return PlanarImage(idx, depth: p.depth)
        }
        let colorIcon = decoded.colorIconNormal.map {
            ColorIcon(normal: $0, selected: decoded.colorIconSelected)
        }
        return try serialize(type: decoded.type ?? .project,
                             defaultTool: decoded.defaultTool ?? "",
                             toolTypes: decoded.toolTypes,
                             drawer: decoded.drawer,
                             planarNormal: planar(decoded.planarNormal),
                             planarSelected: decoded.planarSelected.map(planar),
                             colorIcon: colorIcon)
    }

    // MARK: - DiskObject serialisation

    private static func serialize(type: IconType,
                                  defaultTool: String,
                                  toolTypes: [String],
                                  drawer: DrawerInfo?,
                                  planarNormal: PlanarImage,
                                  planarSelected: PlanarImage?,
                                  colorIcon: ColorIcon?) throws -> [UInt8] {
        var w = BinaryWriter()

        // ---- DiskObject header (78 bytes) ------------------------------
        w.u16(0xE310)                       // do_Magic  (WB_DISKMAGIC)
        w.u16(1)                            // do_Version (WB_DISKVERSION)

        // struct Gadget (44 bytes)
        w.u32(0)                            // ga_NextGadget
        w.i16(0)                            // ga_LeftEdge
        w.i16(0)                            // ga_TopEdge
        w.i16(Int16(planarNormal.width))    // ga_Width
        w.i16(Int16(planarNormal.height))   // ga_Height
        // Flags: GFLG_GADGIMAGE (0x0004); + GFLG_GADGHIMAGE (0x0002) when there
        // is a second image, else GFLG_GADGHCOMP (0x0000) colour-complement.
        let flags: UInt16 = planarSelected != nil ? 0x0006 : 0x0004
        w.u16(flags)                        // ga_Flags
        w.u16(0x0003)                       // ga_Activation (RELVERIFY|GADGIMMEDIATE)
        w.u16(0x0001)                       // ga_GadgetType (BOOLGADGET)
        w.u32(1)                            // ga_GadgetRender (non-NULL: image follows)
        w.u32(planarSelected != nil ? 1 : 0)// ga_SelectRender
        w.u32(0)                            // ga_GadgetText
        w.i32(0)                            // ga_MutualExclude
        w.u32(0)                            // ga_SpecialInfo
        w.u16(0)                            // ga_GadgetID
        w.u32(0)                            // ga_UserData

        w.u8(type.rawValue)                 // do_Type
        w.u8(0)                             // padding

        let hasDefaultTool = !defaultTool.isEmpty
        let hasToolTypes = !toolTypes.isEmpty
        w.u32(hasDefaultTool ? 1 : 0)       // do_DefaultTool
        w.u32(hasToolTypes ? 1 : 0)         // do_ToolTypes
        w.i32(0)                            // do_CurrentX (NO_ICON_POSITION would be 0x80000000)
        w.i32(0)                            // do_CurrentY
        w.u32(drawer != nil ? 1 : 0)        // do_DrawerData (non-NULL: record follows)
        w.u32(0)                            // do_ToolWindow
        w.i32(0)                            // do_StackSize

        // ---- DrawerData (disk/drawer icons only) -----------------------
        if let drawer { writeDrawerData(drawer, into: &w) }

        // ---- Images ----------------------------------------------------
        planarNormal.write(into: &w)
        planarSelected?.write(into: &w)

        // ---- DefaultTool string ----------------------------------------
        if hasDefaultTool { writeString(defaultTool, into: &w) }

        // ---- ToolTypes -------------------------------------------------
        if hasToolTypes {
            // do_ToolTypes is an array of (count + 1) pointers on disk: a 32-bit
            // count field equal to (n + 1) * 4, then each string as a sized blob.
            w.u32(UInt32((toolTypes.count + 1) * 4))
            for tt in toolTypes { writeString(tt, into: &w) }
        }

        // ---- Trailing ColorIcon (GlowIcon) FORM ------------------------
        if let colorIcon { w.bytes(try colorIcon.encode()) }

        return w.data
    }

    /// Writes the 56-byte `struct DrawerData`: an embedded 48-byte `NewWindow`
    /// (most fields are runtime pointers Workbench fills in, so written as 0)
    /// followed by the content scroll offset.
    private static func writeDrawerData(_ d: DrawerInfo, into w: inout BinaryWriter) {
        // struct NewWindow (48 bytes)
        w.i16(d.left)        // LeftEdge
        w.i16(d.top)         // TopEdge
        w.i16(d.width)       // Width
        w.i16(d.height)      // Height
        w.u8(0xFF)           // DetailPen (0xFF = use screen default)
        w.u8(0xFF)           // BlockPen
        w.u32(0)             // IDCMPFlags
        w.u32(0)             // Flags
        w.u32(0)             // FirstGadget
        w.u32(0)             // CheckMark
        w.u32(0)             // Title
        w.u32(0)             // Screen
        w.u32(0)             // BitMap
        w.i16(0)             // MinWidth
        w.i16(0)             // MinHeight
        w.u16(0)             // MaxWidth
        w.u16(0)             // MaxHeight
        w.u16(1)             // Type (1 = WBENCHSCREEN)
        // DrawerData tail (8 bytes)
        w.i32(d.currentX)    // dd_CurrentX
        w.i32(d.currentY)    // dd_CurrentY
    }

    /// Writes an Amiga sized string: 32-bit length (including NUL), bytes, NUL.
    private static func writeString(_ s: String, into w: inout BinaryWriter) {
        // Amiga icons are Latin-1; map non-ASCII conservatively.
        let bytes = s.unicodeScalars.map { UInt8($0.value <= 0xFF ? $0.value : 0x3F) }
        w.u32(UInt32(bytes.count + 1))
        w.bytes(bytes)
        w.u8(0)
    }
}
