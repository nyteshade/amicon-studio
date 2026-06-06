import Foundation

/// The classic **Workbench 1.x** default 4 pens. The 1.x desktop is the famous
/// blue / white / black / orange look (4-bit-per-gun values, hence the 0x_5_A
/// style components).
public let workbench1Palette: [RGB] = [
    RGB(0x00, 0x55, 0xAA), // 0: blue   (background)
    RGB(0xFF, 0xFF, 0xFF), // 1: white  (text / detail)
    RGB(0x00, 0x00, 0x00), // 2: black
    RGB(0xFF, 0x88, 0x00), // 3: orange (highlight)
]

// `workbench4Palette` (the OS2.x/3.x grey 4-pen set) and `magicWB8Palette` (the
// 8-pen MagicWB set, which AmigaOS 3.2 reserves as its first 8 pens) live in
// ClassicIcon.swift. The presets below build on all three.

/// A named, fixed set of Workbench "pens" (palette entries) used to render the
/// classic planar icon, selectable by target release.
///
/// Classic `.info` files store **no palette of their own** — the planar image's
/// indices are interpreted against the live Workbench screen — so matching the
/// target release's pen colours *and ordering* is what makes the icon look right
/// on real hardware. The first `reservedCount` pens are the system pens (desktop
/// background, gadgets, text); for richer 8/16-colour sets they must be kept
/// exactly where they are, while any pens **above** them are free to be filled
/// from the icon's own artwork during colour reduction.
public struct WorkbenchPalette: Identifiable, Equatable, Hashable, Codable {
    public let id: String
    /// Menu label, e.g. "Workbench 3.2 (16)".
    public let name: String
    /// The reserved system pens, in pen order. Always honoured exactly.
    public let systemPens: [RGB]
    /// Total pens the target screen offers. When greater than `systemPens.count`
    /// the extra pens are generated from the artwork by the quantiser, with the
    /// system pens kept reserved at the front.
    public let totalColors: Int

    public init(id: String, name: String, systemPens: [RGB], totalColors: Int) {
        self.id = id
        self.name = name
        self.systemPens = systemPens
        self.totalColors = max(systemPens.count, totalColors)
    }

    /// Upper bound on reserved pens (a screen offers at most 256 pens).
    static let maxPens = 256

    /// A user-defined palette (not one of the named presets).
    public static func custom(systemPens: [RGB], totalColors: Int) -> WorkbenchPalette {
        WorkbenchPalette(id: "custom", name: "Custom", systemPens: systemPens, totalColors: totalColors)
    }

    /// Whether this palette has been edited away from a named preset.
    public var isCustom: Bool { id == "custom" }

    /// Number of leading pens that are fixed system pens.
    public var reservedCount: Int { systemPens.count }

    /// Bitplane depth needed to represent every pen index.
    public var depth: Int { max(1, Int(ceil(log2(Double(max(2, totalColors)))))) }
}

public extension WorkbenchPalette {
    /// Workbench 1.x — 4 pens (blue / white / black / orange).
    static let workbench1_4 = WorkbenchPalette(
        id: "wb1.4", name: "Workbench 1.x (4)", systemPens: workbench1Palette, totalColors: 4)

    /// Workbench 2.x / 3.0 / 3.1 — the grey 4-pen default.
    static let workbench2_4 = WorkbenchPalette(
        id: "wb2.4", name: "Workbench 2.x / 3.1 (4)", systemPens: workbench4Palette, totalColors: 4)

    /// Workbench 3.2 — 8 reserved system pens (MagicWB-compatible, as 3.2 uses
    /// for its first eight pens).
    static let workbench32_8 = WorkbenchPalette(
        id: "wb32.8", name: "Workbench 3.2 (8)", systemPens: magicWB8Palette, totalColors: 8)

    /// Workbench 3.2 — 8 reserved system pens + 8 artwork pens (16 total).
    static let workbench32_16 = WorkbenchPalette(
        id: "wb32.16", name: "Workbench 3.2 (16)", systemPens: magicWB8Palette, totalColors: 16)

    /// MagicWB — the de-facto 8-pen standard.
    static let magicWB_8 = WorkbenchPalette(
        id: "mwb.8", name: "MagicWB (8)", systemPens: magicWB8Palette, totalColors: 8)

    /// MagicWB — 8 reserved pens + 8 artwork pens (16 total).
    static let magicWB_16 = WorkbenchPalette(
        id: "mwb.16", name: "MagicWB (16)", systemPens: magicWB8Palette, totalColors: 16)

    /// All presets, in menu order.
    static let presets: [WorkbenchPalette] = [
        .workbench1_4, .workbench2_4, .workbench32_8, .workbench32_16, .magicWB_8, .magicWB_16,
    ]

    static func preset(id: String) -> WorkbenchPalette? { presets.first { $0.id == id } }

    /// Resolves a preset id, tolerating the legacy short names ("wb4",
    /// "magicwb8") used before this enum existed. Falls back to the WB2/3.1 4-pen
    /// default.
    static func resolve(_ idOrLegacyName: String) -> WorkbenchPalette {
        if let p = preset(id: idOrLegacyName) { return p }
        switch idOrLegacyName {
        case "wb4": return .workbench2_4
        case "magicwb8": return .magicWB_8
        default: return .workbench2_4
        }
    }
}
