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

private let sharedCIContext = CIContext(options: [.workingColorSpace: NSNull()])

private extension RGBAImage {
    /// Loads a stored original and runs the CoreImage effect stack over it,
    /// returning a fresh RGBA buffer ready for the kit's compositor.
    static func effected(from data: Data, effects: [EffectInstance]) -> RGBAImage? {
        guard let ci = CIImage(data: data) else { return RGBAImage(data: data) }
        let out = EffectPipeline.apply(effects, to: ci)
        let rect = ci.extent.isInfinite ? out.extent : ci.extent
        guard rect.isFinite, !rect.isEmpty,
              let cg = sharedCIContext.createCGImage(out, from: rect) else {
            return RGBAImage(data: data)
        }
        return RGBAImage(cgImage: cg)
    }
}

/// Bridges the app's stored originals to AmigaIconKit for both live preview and
/// `.info` export. All composition (centre-in-canvas, glow) is driven by the
/// item's `RenderSettings` and always works from the full-resolution originals.
enum IconRenderer {

    /// Accurate preview images for the unclicked/clicked states **and** the
    /// classic planar fallback.
    ///
    /// Crucially, these are produced by encoding the real `.info` bytes and
    /// decoding them back — so the preview shows exactly what gets written: the
    /// reduced GlowIcon palette, the transparent index, and the low-colour
    /// planar image, rather than the full-colour source. What you see is what
    /// the Amiga gets.
    static func previews(for item: IconItem) -> (normal: NSImage?, clicked: NSImage?, planar: NSImage?) {
        guard let data = infoData(for: item),
              let decoded = try? IconDecoder.decode([UInt8](data)) else {
            return (nil, nil, nil)
        }
        let opts = item.settings.makeOptions()
        // The planar image carries no palette of its own; render it against the
        // chosen Workbench palette, drawing the background index transparent.
        let planarRGBA = decoded.planarNormal.rgba(palette: opts.planarPalette, transparentIndex: 0)

        // Unclicked: the GlowIcon if one was written, otherwise the planar truth.
        let normal = (decoded.colorIconNormal?.rgba() ?? planarRGBA).nsImage

        // Clicked: the GlowIcon selected state (explicit image or auto-glow),
        // else an explicit planar selected image, else nothing.
        let clicked: NSImage?
        if let sel = decoded.colorIconSelected {
            clicked = sel.rgba().nsImage
        } else if let planarSel = decoded.planarSelected {
            clicked = planarSel.rgba(palette: opts.planarPalette, transparentIndex: 0).nsImage
        } else {
            clicked = nil
        }

        return (normal, clicked, planarRGBA.nsImage)
    }

    /// Builds the `.info` byte stream for a single icon, with effects applied.
    static func infoData(for item: IconItem) -> Data? {
        guard let nData = item.normalPNG,
              let normal = RGBAImage.effected(from: nData, effects: item.effects) else { return nil }
        let selected = item.clickedPNG.flatMap { RGBAImage.effected(from: $0, effects: item.effects) }
        guard let bytes = try? IconWriter.build(normal: normal, selected: selected,
                                                options: item.settings.makeOptions()) else { return nil }
        return Data(bytes)
    }
}
#endif
