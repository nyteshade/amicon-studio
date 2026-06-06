#if os(macOS)
import Foundation
import AmigaIconKit

/// A badge/emblem overlaid on the artwork. Position and size are stored
/// normalised (relative to the artwork) so they're resolution-independent and
/// survive re-rendering at any target size.
struct Badge: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Overlay image, full-resolution PNG.
    var png: Data
    /// Centre of the badge, 0...1 across the artwork (x = left→right, y = top→bottom).
    var x: Double = 0.72
    var y: Double = 0.72
    /// Longer side of the badge as a fraction of the artwork's smaller dimension.
    var scale: Double = 0.4
}

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
    var preserveAspect = false // non-square canvas hugging the artwork

    // Clicked-state glow
    var autoGlow = true
    var glowRadius = 3
    var glowColorHex = "FF8B00"

    // Outline (solid stroke around the artwork; 0 = off)
    var outlineThickness = 0
    var outlineColorHex = "000000"

    // Shadows (any number; outer and/or inner)
    var shadows: [Shadow] = []

    // Posterize levels per channel before reduction (0/1 = off)
    var posterizeLevels = 0

    // Orientation (applied to the source before fitting)
    var flipH = false
    var flipV = false
    var rotateQuarters = 0
    var blurRadius = 0
    var tintColorHex = "000000"
    var tintAmount = 0.0

    // Classic planar (OS1–3): smaller, as was typical
    var planarCanvas = 40
    var planarContent = 36
    /// The Workbench pen set used for the planar fallback — a named preset or an
    /// edited custom palette (its exact pen RGBs are stored with the project).
    var palette: WorkbenchPalette = .workbench2_4

    // Image quality
    var resample: ResampleFilter = .smooth
    var planarDither: DitherMode = .floydSteinberg

    // Misc
    var writeNewIcons = false // experimental
    var defaultTool = ""
    var toolTypes: [String] = []
    /// Drawer window record (disk/drawer icons). When nil, one is auto-generated
    /// for drawer/disk types on export; preserved as-is when importing.
    var drawer: DrawerInfo? = nil

    func makeOptions() -> IconOptions {
        var o = IconOptions()
        o.type = IconType(rawValue: UInt8(iconType)) ?? .project
        o.writeColorIcon = writeColorIcon
        o.colorCanvasSize = colorCanvas
        o.colorContentSize = colorContent
        o.colorMaxColors = maxColors
        o.compressColorIcon = compress
        o.preserveAspectRatio = preserveAspect
        o.autoGlow = autoGlow
        o.glowRadius = glowRadius
        if let c = RGB(hex: glowColorHex) { o.glowColor = c }
        o.outlineThickness = outlineThickness
        if let c = RGB(hex: outlineColorHex) { o.outlineColor = c }
        o.shadows = shadows
        o.posterizeLevels = posterizeLevels
        o.flipHorizontal = flipH
        o.flipVertical = flipV
        o.rotateQuarters = rotateQuarters
        o.blurRadius = blurRadius
        if let c = RGB(hex: tintColorHex) { o.tintColor = c }
        o.tintAmount = tintAmount
        o.planarCanvasSize = planarCanvas
        o.planarContentSize = planarContent
        o.planarPalette = palette
        o.resampleFilter = resample
        o.planarDither = planarDither
        o.writeNewIcons = writeNewIcons
        o.defaultTool = defaultTool.trimmingCharacters(in: .whitespaces)
        o.toolTypes = toolTypes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let drawer {
            o.drawerData = drawer
        } else if o.type == .drawer || o.type == .disk {
            o.drawerData = DrawerInfo() // sensible default window for drawers
        }
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
    /// Badges/emblems overlaid on the artwork, in draw order.
    var badges: [Badge] = []
    /// CoreImage effect stack applied (non-destructively) to the originals.
    var effects: [EffectInstance] = []
    var settings = RenderSettings()
}

/// The project document model: a collection of icons, like a CandyBar set.
struct IconProject: Codable, Equatable {
    var items: [IconItem] = []
}

// Model types use synthesized `Codable` — there are no legacy documents to
// migrate, so the schema is free to change with the code.

extension RGB {
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }
    var hexString: String { String(format: "%02X%02X%02X", r, g, b) }
}
#endif
