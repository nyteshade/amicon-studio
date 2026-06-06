#if os(macOS)
import AppKit
import CoreImage
import AmigaIconKit

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

    /// Composed preview images for the normal and clicked states, at the
    /// ColorIcon canvas size.
    static func previews(for item: IconItem) -> (normal: NSImage?, clicked: NSImage?) {
        guard let nData = item.normalPNG,
              let normal = RGBAImage.effected(from: nData, effects: item.effects) else {
            return (nil, nil)
        }
        let opts = item.settings.makeOptions()
        let normRGBA = normal.centered(inCanvas: opts.colorCanvasSize, contentSize: opts.colorContentSize)

        let clickedRGBA: RGBAImage?
        if let cData = item.clickedPNG, let clicked = RGBAImage.effected(from: cData, effects: item.effects) {
            clickedRGBA = clicked.centered(inCanvas: opts.colorCanvasSize, contentSize: opts.colorContentSize)
        } else if opts.autoGlow {
            let margin = (opts.colorCanvasSize - opts.colorContentSize) / 2
            let r = max(1, min(opts.glowRadius, max(1, margin)))
            clickedRGBA = normRGBA.addingGlow(radius: r,
                                              color: (opts.glowColor.r, opts.glowColor.g, opts.glowColor.b))
        } else {
            clickedRGBA = nil
        }
        return (normRGBA.nsImage, clickedRGBA?.nsImage)
    }

    /// Builds the `.info` byte stream for a single icon, with effects applied.
    static func infoData(for item: IconItem) -> Data? {
        guard let nData = item.normalPNG,
              let normal = RGBAImage.effected(from: nData, effects: item.effects) else { return nil }
        let selected = item.clickedPNG.flatMap { RGBAImage.effected(from: $0, effects: item.effects) }
        let bytes = IconWriter.build(normal: normal, selected: selected, options: item.settings.makeOptions())
        return Data(bytes)
    }
}
#endif
