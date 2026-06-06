#if os(macOS)
import Foundation
import AmigaIconKit

/// Where a badge/emblem overlay sits on the artwork.
enum BadgeCorner: String, Codable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, center

    var label: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .center: return "Center"
        }
    }

    /// Top-left origin to stamp a `badgeW × badgeH` overlay onto a `baseW × baseH`
    /// image, inset by `margin`.
    func origin(baseW: Int, baseH: Int, badgeW: Int, badgeH: Int, margin: Int) -> (x: Int, y: Int) {
        let maxX = max(0, baseW - badgeW), maxY = max(0, baseH - badgeH)
        switch self {
        case .topLeft:     return (margin, margin)
        case .topRight:    return (maxX - margin, margin)
        case .bottomLeft:  return (margin, maxY - margin)
        case .bottomRight: return (maxX - margin, maxY - margin)
        case .center:      return (maxX / 2, maxY / 2)
        }
    }
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

    // Classic planar (OS1–3): smaller, as was typical
    var planarCanvas = 40
    var planarContent = 36
    /// The Workbench pen set used for the planar fallback — a named preset or an
    /// edited custom palette (its exact pen RGBs are stored with the project).
    var palette: WorkbenchPalette = .workbench2_4

    // Image quality
    var resample: ResampleFilter = .smooth
    var planarDither: DitherMode = .floydSteinberg

    // Badge / emblem overlay placement (the image itself is on IconItem)
    var badgeCorner: BadgeCorner = .bottomRight
    var badgeScale: Double = 0.45 // fraction of the artwork's smaller side

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
    /// Optional badge/emblem overlaid on the artwork (full-res PNG).
    var badgePNG: Data?
    /// CoreImage effect stack applied (non-destructively) to the originals.
    var effects: [EffectInstance] = []
    var settings = RenderSettings()
}

/// The project document model: a collection of icons, like a CandyBar set.
struct IconProject: Codable, Equatable {
    var items: [IconItem] = []
}

// MARK: - Forward-compatible decoding
//
// Encoding stays synthesized (new files carry every key), but decoding is made
// tolerant: any key absent from a project saved by an older build falls back to
// its default. Without this, adding a settings field would make existing
// `.amigaicons` documents fail to open. Each stored property is assigned, so the
// compiler flags a forgotten field.

extension RenderSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RenderSettings()
        iconType       = try c.decodeIfPresent(Int.self, forKey: .iconType) ?? d.iconType
        writeColorIcon = try c.decodeIfPresent(Bool.self, forKey: .writeColorIcon) ?? d.writeColorIcon
        colorCanvas    = try c.decodeIfPresent(Int.self, forKey: .colorCanvas) ?? d.colorCanvas
        colorContent   = try c.decodeIfPresent(Int.self, forKey: .colorContent) ?? d.colorContent
        maxColors      = try c.decodeIfPresent(Int.self, forKey: .maxColors) ?? d.maxColors
        compress       = try c.decodeIfPresent(Bool.self, forKey: .compress) ?? d.compress
        preserveAspect = try c.decodeIfPresent(Bool.self, forKey: .preserveAspect) ?? d.preserveAspect
        autoGlow       = try c.decodeIfPresent(Bool.self, forKey: .autoGlow) ?? d.autoGlow
        glowRadius     = try c.decodeIfPresent(Int.self, forKey: .glowRadius) ?? d.glowRadius
        glowColorHex   = try c.decodeIfPresent(String.self, forKey: .glowColorHex) ?? d.glowColorHex
        planarCanvas   = try c.decodeIfPresent(Int.self, forKey: .planarCanvas) ?? d.planarCanvas
        planarContent  = try c.decodeIfPresent(Int.self, forKey: .planarContent) ?? d.planarContent
        palette        = try c.decodeIfPresent(WorkbenchPalette.self, forKey: .palette) ?? d.palette
        resample       = try c.decodeIfPresent(ResampleFilter.self, forKey: .resample) ?? d.resample
        planarDither   = try c.decodeIfPresent(DitherMode.self, forKey: .planarDither) ?? d.planarDither
        badgeCorner    = try c.decodeIfPresent(BadgeCorner.self, forKey: .badgeCorner) ?? d.badgeCorner
        badgeScale     = try c.decodeIfPresent(Double.self, forKey: .badgeScale) ?? d.badgeScale
        writeNewIcons  = try c.decodeIfPresent(Bool.self, forKey: .writeNewIcons) ?? d.writeNewIcons
        defaultTool    = try c.decodeIfPresent(String.self, forKey: .defaultTool) ?? d.defaultTool
        toolTypes      = try c.decodeIfPresent([String].self, forKey: .toolTypes) ?? d.toolTypes
        drawer         = try c.decodeIfPresent(DrawerInfo.self, forKey: .drawer) ?? d.drawer
    }
}

extension IconItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IconItem()
        id         = try c.decodeIfPresent(UUID.self, forKey: .id) ?? d.id
        name       = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        normalPNG  = try c.decodeIfPresent(Data.self, forKey: .normalPNG)
        clickedPNG = try c.decodeIfPresent(Data.self, forKey: .clickedPNG)
        badgePNG   = try c.decodeIfPresent(Data.self, forKey: .badgePNG)
        effects    = try c.decodeIfPresent([EffectInstance].self, forKey: .effects) ?? d.effects
        settings   = try c.decodeIfPresent(RenderSettings.self, forKey: .settings) ?? d.settings
    }
}

extension RGB {
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }
    var hexString: String { String(format: "%02X%02X%02X", r, g, b) }
}
#endif
