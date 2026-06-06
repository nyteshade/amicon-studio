#if os(macOS)
import AppKit
import CoreImage
import AmigaIconKit
import AmigaIconImageIO // RGBAImage <-> Data/CGImage (pngData, init(data:)/(cgImage:))

extension RGBAImage {
    /// Converts to an `NSImage` for on-screen preview.
    var nsImage: NSImage? {
        guard let data = pngData() else { return nil }
        return NSImage(data: data)
    }
}

/// Bridges the app's stored originals to AmigaIconKit for both live preview and
/// `.info` export. All composition (centre-in-canvas, glow) is driven by the
/// item's `RenderSettings` and always works from the full-resolution originals.
enum IconRenderer {

    private static let sharedCIContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// Accurate preview images for the unclicked/clicked states **and** the
    /// classic planar fallback.
    ///
    /// Crucially, these are produced by encoding the real `.info` bytes and
    /// decoding them back — so the preview shows exactly what gets written: the
    /// reduced GlowIcon palette, the transparent index, and the low-colour
    /// planar image, rather than the full-colour source. What you see is what
    /// the Amiga gets.
    static func previews(for item: IconItem) -> (normal: NSImage?, clicked: NSImage?, planar: NSImage?) {
        guard let nData = item.normalPNG,
              let normal = effected(from: nData, effects: item.effects) else {
            return (nil, nil, nil)
        }
        let opts = item.settings.makeOptions()
        let selected = item.clickedPNG.flatMap { effected(from: $0, effects: item.effects) }

        // Encode then decode, so the colour (GlowIcon) states reflect the real
        // reduced palette and transparent index that get written.
        guard let bytes = try? IconWriter.build(normal: normal, selected: selected, options: opts),
              let decoded = try? IconDecoder.decode([UInt8](bytes)) else {
            return (nil, nil, nil)
        }

        // Planar fallback: render the exact pen-mapped image the writer embeds,
        // with the Workbench background pen (0) shown transparent.
        let planarImg = planarPreview(for: normal, options: opts)

        // Unclicked: the GlowIcon if one was written, otherwise the planar truth.
        let normalImg = (decoded.colorIconNormal?.rgba() ?? planarImg).nsImage

        // Clicked: the GlowIcon selected state (explicit image or auto-glow),
        // else an explicit planar selected image, else nothing.
        let clicked: NSImage?
        if let sel = decoded.colorIconSelected {
            clicked = sel.rgba().nsImage
        } else if let sel = selected {
            clicked = planarPreview(for: sel, options: opts).nsImage
        } else {
            clicked = nil
        }

        return (normalImg, clicked, planarImg.nsImage)
    }

    /// The planar pen-mapped image the writer would embed, with pen 0 (the
    /// Workbench background) made transparent for display against a checkerboard.
    private static func planarPreview(for source: RGBAImage, options: IconOptions) -> RGBAImage {
        var indexed = IconWriter.planarIndexed(for: source, options: options)
        indexed.transparentIndex = 0
        return indexed.rgba()
    }

    /// Loads a stored original and runs the CoreImage effect stack over it,
    /// returning a fresh RGBA buffer ready for the kit's compositor.
    private static func effected(from data: Data, effects: [EffectInstance]) -> RGBAImage? {
        guard let ci = CIImage(data: data) else { return RGBAImage(data: data) }
        let out = EffectPipeline.apply(effects, to: ci)
        let rect = ci.extent.isInfinite ? out.extent : ci.extent
        guard !rect.isInfinite, !rect.isNull, !rect.isEmpty,
              let cg = sharedCIContext.createCGImage(out, from: rect) else {
            return RGBAImage(data: data)
        }
        return RGBAImage(cgImage: cg)
    }

    /// Builds the `.info` byte stream for a single icon, with effects applied.
    static func infoData(for item: IconItem) -> Data? {
        guard let nData = item.normalPNG,
              let normal = effected(from: nData, effects: item.effects) else { return nil }
        let selected = item.clickedPNG.flatMap { effected(from: $0, effects: item.effects) }
        guard let bytes = try? IconWriter.build(normal: normal, selected: selected,
                                                options: item.settings.makeOptions()) else { return nil }
        return Data(bytes)
    }

    /// Builds a project item from a source image file (PNG/JPEG/TIFF/HEIC…),
    /// normalising it to PNG at full resolution. Returns `nil` if the data isn't
    /// a decodable image.
    static func item(fromImage data: Data, name: String) -> IconItem? {
        guard let rgba = RGBAImage(data: data), let png = rgba.pngData() else { return nil }
        var item = IconItem()
        item.name = name
        item.normalPNG = png
        return item
    }

    /// Builds an editable project item from an existing `.info` file's bytes,
    /// so a user can open an icon, tweak it, and re-export. The highest-fidelity
    /// image available (the GlowIcon, else the planar fallback) becomes the
    /// stored original; type, default tool and tool types carry over.
    static func item(fromInfo data: Data, name: String) -> IconItem? {
        guard let decoded = try? IconDecoder.decode([UInt8](data)) else { return nil }
        var item = IconItem()
        item.name = name
        let planarPalette: [RGB] = decoded.planarNormal.depth <= 2 ? workbench4Palette : magicWB8Palette
        item.normalPNG = decoded.renderedNormal(planarPalette: planarPalette).pngData()
        if let sel = decoded.renderedSelected(planarPalette: planarPalette) {
            item.clickedPNG = sel.pngData()
            item.settings.autoGlow = false // preserve the imported clicked state as-is
        }
        if let t = decoded.type { item.settings.iconType = Int(t.rawValue) }
        item.settings.drawer = decoded.drawer // preserve the original window record
        item.settings.defaultTool = decoded.defaultTool ?? ""
        // Keep the user's tool types; drop any embedded NewIcons (IMn=) payload.
        item.settings.toolTypes = decoded.toolTypes.filter { !$0.hasPrefix("IM1=") && !$0.hasPrefix("IM2=") }
        return item
    }
}
#endif
