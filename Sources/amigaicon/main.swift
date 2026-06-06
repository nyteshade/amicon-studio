import Foundation
import AmigaIconKit

// A small command-line front-end for AmigaIconKit. Image loading uses ImageIO,
// so the tool itself is macOS-only; on other platforms it builds (so the whole
// package, and CI, stays green) but just prints a notice. Use AmigaIconKit
// directly elsewhere.
#if canImport(CoreGraphics) && canImport(ImageIO)
import AmigaIconImageIO // RGBAImage(contentsOf:) ImageIO loader

let usage = """
amigaicon — write Amiga .info icons (classic planar + OS3.5+ 24-bit GlowIcons)

USAGE:
  amigaicon --normal <image> [--selected <image>] [--out <file.info>] [options]

INPUT:
  --normal <path>        Unclicked-state artwork (PNG/JPEG/TIFF/HEIC/…). Required.
  --selected <path>      Clicked-state artwork. If omitted, a glow is generated.
  --out <path>           Output .info file. Defaults to <normal>.info

ICON:
  --type <t>             disk|drawer|tool|project|garbage|device|kick|appicon
                         (default: project)
  --default-tool <s>     do_DefaultTool string (e.g. a viewer path)
  --tooltype <s>         Add a tool type (repeatable)

PLANAR (OS1–3 fallback, always written):
  --planar-canvas <n>    On-disk planar size (default 40)
  --planar-content <n>   Artwork fit size within the canvas (default 36)
  --palette <p>          Workbench pen set for colour reduction:
                           wb1     Workbench 1.x (4)
                           wb2     Workbench 2.x / 3.1 (4)   [default]
                           wb32-8  Workbench 3.2 (8)
                           wb32-16 Workbench 3.2 (16, 8 pens reserved)
                           mwb8    MagicWB (8)
                           mwb16   MagicWB (16, 8 pens reserved)

COLORICON / GLOWICON (OS3.5+, 24-bit):
  --no-color             Don't write the ColorIcon block
  --color-canvas <n>     Canvas size (default 54)
  --color-content <n>    Artwork fit size (default 48)
  --max-colors <n>       Palette cap, 2–256 (default 256)
  --no-compress          Store image/palette uncompressed (RLE is default)

GLOW (clicked state, when --selected is not given):
  --no-glow              Don't auto-generate a glowing clicked state
  --glow-radius <n>      Glow thickness in pixels (default 3)
  --glow-color <hex>     RRGGBB (default FF8B00)

OTHER:
  --newicons             Also embed an (experimental) NewIcons tool-type image
  -h, --help             Show this help
"""

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

// ---- Parse arguments --------------------------------------------------------
var args = Array(CommandLine.arguments.dropFirst())
var normalPath: String?
var selectedPath: String?
var outPath: String?
var options = IconOptions()

func nextValue(_ flag: String) -> String {
    guard !args.isEmpty else { fail("\(flag) requires a value") }
    return args.removeFirst()
}

while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "-h", "--help": print(usage); exit(0)
    case "--normal": normalPath = nextValue(arg)
    case "--selected": selectedPath = nextValue(arg)
    case "--out": outPath = nextValue(arg)
    case "--type":
        guard let t = parseType(nextValue(arg)) else { fail("unknown --type") }
        options.type = t
    case "--default-tool": options.defaultTool = nextValue(arg)
    case "--tooltype": options.toolTypes.append(nextValue(arg))
    case "--planar-canvas": options.planarCanvasSize = Int(nextValue(arg)) ?? options.planarCanvasSize
    case "--planar-content": options.planarContentSize = Int(nextValue(arg)) ?? options.planarContentSize
    case "--palette":
        guard let wb = parsePalette(nextValue(arg)) else { fail("unknown --palette") }
        options.planarPalette = wb
    case "--no-color": options.writeColorIcon = false
    case "--color-canvas": options.colorCanvasSize = Int(nextValue(arg)) ?? options.colorCanvasSize
    case "--color-content": options.colorContentSize = Int(nextValue(arg)) ?? options.colorContentSize
    case "--max-colors": options.colorMaxColors = max(2, min(256, Int(nextValue(arg)) ?? 256))
    case "--no-compress": options.compressColorIcon = false
    case "--no-glow": options.autoGlow = false
    case "--glow-radius": options.glowRadius = Int(nextValue(arg)) ?? options.glowRadius
    case "--glow-color":
        if let rgb = parseHexColor(nextValue(arg)) { options.glowColor = rgb }
    case "--newicons": options.writeNewIcons = true
    default: fail("unknown argument: \(arg)")
    }
}

guard let normalPath else { print(usage); exit(args.isEmpty ? 0 : 1) }
let out = outPath ?? (normalPath as NSString).deletingPathExtension + ".info"

guard let normal = RGBAImage(contentsOf: URL(fileURLWithPath: normalPath)) else {
    fail("could not load image: \(normalPath)")
}
var selected: RGBAImage?
if let sp = selectedPath {
    guard let s = RGBAImage(contentsOf: URL(fileURLWithPath: sp)) else { fail("could not load image: \(sp)") }
    selected = s
}

let bytes: [UInt8]
do {
    bytes = try IconWriter.build(normal: normal, selected: selected, options: options)
} catch {
    fail("could not build icon: \(error)")
}
do {
    try Data(bytes).write(to: URL(fileURLWithPath: out))
    print("wrote \(out) (\(bytes.count) bytes)")
} catch {
    fail("could not write \(out): \(error.localizedDescription)")
}

// ---- Helpers ----------------------------------------------------------------
func parseType(_ s: String) -> IconType? {
    switch s.lowercased() {
    case "disk": return .disk
    case "drawer": return .drawer
    case "tool": return .tool
    case "project": return .project
    case "garbage", "trashcan": return .garbage
    case "device": return .device
    case "kick": return .kick
    case "appicon": return .appIcon
    default: return nil
    }
}

func parsePalette(_ s: String) -> WorkbenchPalette? {
    switch s.lowercased() {
    case "wb1", "wb1.x", "1.x":            return .workbench1_4
    case "wb2", "wb3.1", "wb31", "wb4":    return .workbench2_4
    case "wb32", "wb32-8", "wb32.8", "3.2": return .workbench32_8
    case "wb32-16", "wb32.16":             return .workbench32_16
    case "mwb", "mwb8", "magicwb8", "magicwb": return .magicWB_8
    case "mwb16", "magicwb16":             return .magicWB_16
    default:                                return nil
    }
}

func parseHexColor(_ s: String) -> RGB? {
    let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
    guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
    return RGB(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
}

#else
FileHandle.standardError.write(Data("amigaicon requires macOS (ImageIO) for image loading.\n".utf8))
exit(1)
#endif
