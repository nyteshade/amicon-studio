import Foundation

/// Workbench icon type (`do_Type` in the `DiskObject`).
public enum IconType: UInt8 {
    case disk    = 1  // WBDISK
    case drawer  = 2  // WBDRAWER
    case tool    = 3  // WBTOOL
    case project = 4  // WBPROJECT
    case garbage = 5  // WBGARBAGE (trashcan)
    case device  = 6  // WBDEVICE
    case kick    = 7  // WBKICK
    case appIcon = 8  // WBAPPICON
}

/// The standard 4-colour Workbench palette (OS2.0/3.x default), used to render
/// the classic planar fallback image. Classic `.info` files store no palette of
/// their own — indices are interpreted against the live Workbench screen — so a
/// fixed, conventional palette is the sensible target for colour matching.
public let workbench4Palette: [RGB] = [
    RGB(0x95, 0x95, 0x95), // 0: grey  (background / "transparent")
    RGB(0x00, 0x00, 0x00), // 1: black
    RGB(0xFF, 0xFF, 0xFF), // 2: white
    RGB(0x3B, 0x67, 0xA2), // 3: blue
]

/// The MagicWB 8-colour palette, a de-facto OS3.x standard for richer icons.
public let magicWB8Palette: [RGB] = [
    RGB(0x95, 0x95, 0x95), // 0: grey
    RGB(0x00, 0x00, 0x00), // 1: black
    RGB(0xFF, 0xFF, 0xFF), // 2: white
    RGB(0x3B, 0x67, 0xA2), // 3: blue
    RGB(0x7B, 0x7B, 0x7B), // 4: dark grey
    RGB(0xAF, 0xAF, 0xAF), // 5: light grey
    RGB(0xAA, 0x90, 0x7C), // 6: tan
    RGB(0xFF, 0xA9, 0x97), // 7: salmon
]

/// Encodes one classic Amiga `Image`: bitplanes, each row word-aligned (padded
/// to a 16-bit boundary), planes stored sequentially.
struct PlanarImage {
    let width: Int
    let height: Int
    let depth: Int
    /// Plane data, `depth` planes of `rowBytes * height` bytes.
    let planeData: [UInt8]

    /// Bytes per row for a single plane (word aligned).
    static func rowBytes(_ width: Int) -> Int { ((width + 15) / 16) * 2 }

    init(_ indexed: IndexedImage, depth: Int) {
        self.width = indexed.width
        self.height = indexed.height
        self.depth = depth
        let rb = PlanarImage.rowBytes(indexed.width)
        var out = [UInt8](repeating: 0, count: rb * indexed.height * depth)
        for plane in 0..<depth {
            let planeBase = plane * rb * indexed.height
            for y in 0..<indexed.height {
                let rowBase = planeBase + y * rb
                for x in 0..<indexed.width {
                    let bit = (indexed.indices[y * indexed.width + x] >> plane) & 1
                    if bit != 0 {
                        out[rowBase + (x >> 3)] |= UInt8(0x80 >> (x & 7))
                    }
                }
            }
        }
        self.planeData = out
    }

    /// Serialises the 20-byte `struct Image` header followed by plane data.
    func write(into w: inout BinaryWriter) {
        w.i16(0)               // LeftEdge
        w.i16(0)               // TopEdge
        w.i16(Int16(width))    // Width
        w.i16(Int16(height))   // Height
        w.i16(Int16(depth))    // Depth
        w.u32(1)               // ImageData pointer (non-NULL marker; reader only tests for 0)
        w.u8(UInt8((1 << depth) - 1)) // PlanePick: low `depth` planes used
        w.u8(0)                // PlaneOnOff
        w.u32(0)               // NextImage (NULL)
        w.bytes(planeData)
    }
}
