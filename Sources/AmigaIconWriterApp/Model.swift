import Foundation
import AmigaIconKit

/// Per-icon render settings. Defaults follow the conventions discussed:
/// a small, few-colour planar image for OS1–3, and a 48×48-in-54×54 24-bit
/// GlowIcon for OS3.5+ with an auto-generated glow on the clicked state.
struct RenderSettings: Codable, Equatable {
    var iconType: Int = Int(IconType.project.rawValue)

    // ColorIcon / GlowIcon (OS3.5+)
    var writeColorIcon = true
    var colorCanvas = 54
    var colorContent = 48
    var maxColors = 256
    var compress = true

    // Clicked-state glow
    var autoGlow = true
    var glowRadius = 3
    var glowColorHex = "FF8B00"

    // Classic planar (OS1–3): smaller, as was typical
    var planarCanvas = 40
    var planarContent = 36
    /// A `WorkbenchPalette` preset id (see `WorkbenchPalette.presets`).
    var paletteName = WorkbenchPalette.workbench2_4.id

    // Misc
    var writeNewIcons = false // experimental
    var defaultTool = ""
    var toolTypes: [String] = []

    func makeOptions() -> IconOptions {
        var o = IconOptions()
        o.type = IconType(rawValue: UInt8(iconType)) ?? .project
        o.writeColorIcon = writeColorIcon
        o.colorCanvasSize = colorCanvas
        o.colorContentSize = colorContent
        o.colorMaxColors = maxColors
        o.compressColorIcon = compress
        o.autoGlow = autoGlow
        o.glowRadius = glowRadius
        if let c = RGB(hex: glowColorHex) { o.glowColor = c }
        o.planarCanvasSize = planarCanvas
        o.planarContentSize = planarContent
        o.planarPalette = WorkbenchPalette.resolve(paletteName)
        o.writeNewIcons = writeNewIcons
        o.defaultTool = defaultTool
        o.toolTypes = toolTypes
        return o
    }
}

/// One icon in the project. Crucially, this stores the **original dropped
/// images** (full resolution, as PNG) so the icon can be re-rendered at any
/// target size later without quality loss — the CandyBar-style workflow.
struct IconItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Untitled"
    /// Original unclicked-state artwork, as dropped (PNG-encoded, full res).
    var normalPNG: Data?
    /// Original clicked-state artwork, if the user provided one explicitly.
    var clickedPNG: Data?
    /// CoreImage effect stack applied (non-destructively) to the originals.
    var effects: [EffectInstance] = []
    var settings = RenderSettings()
}

/// The project document model: a collection of icons, like a CandyBar set.
struct IconProject: Codable, Equatable {
    var items: [IconItem] = []
}

extension RGB {
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }
    var hexString: String { String(format: "%02X%02X%02X", r, g, b) }
}
