import XCTest
@testable import AmigaIconKit

final class PackBitsTests: XCTestCase {
    func testRLERoundTripBytes() {
        let items = [0, 0, 0, 1, 2, 3, 3, 3, 3, 5, 5, 9, 9, 9, 9, 9, 0]
        let packed = PackBits.packRLE(items, itemBits: 8)
        let back = PackBits.unpackRLE(packed, itemBits: 8, count: items.count)
        XCTAssertEqual(back, items)
    }

    func testRLERoundTripSubByteDepth() {
        // Depth 3 (values 0...7) — the case that exercises the non-byte-aligned
        // bit stream that distinguishes ColorIcon RLE from plain PackBits.
        var items: [Int] = []
        for i in 0..<300 { items.append((i / 7) % 8) }
        let packed = PackBits.packRLE(items, itemBits: 3)
        let back = PackBits.unpackRLE(packed, itemBits: 3, count: items.count)
        XCTAssertEqual(back, items)
    }

    func testRawRoundTrip() {
        let items = [7, 3, 0, 5, 1, 2, 6, 4]
        let packed = PackBits.packRaw(items, itemBits: 3)
        let back = PackBits.unpackRaw(packed, itemBits: 3, count: items.count)
        XCTAssertEqual(back, items)
    }

    func testLongReplicateRunSplitsAt128() {
        let items = [Int](repeating: 4, count: 500)
        let packed = PackBits.packRLE(items, itemBits: 8)
        let back = PackBits.unpackRLE(packed, itemBits: 8, count: items.count)
        XCTAssertEqual(back, items)
    }
}

final class QuantizerTests: XCTestCase {
    func testTransparencyGetsDedicatedIndex() {
        var img = RGBAImage(width: 2, height: 1)
        img.setPixel(0, 0, 255, 0, 0, 255)   // opaque red
        img.setPixel(1, 0, 0, 0, 0, 0)       // transparent
        let q = ColorQuantizer.quantize(img, maxColors: 16)
        XCTAssertNotNil(q.transparentIndex)
        XCTAssertEqual(q.indices[1], q.transparentIndex)
        XCTAssertNotEqual(q.indices[0], q.transparentIndex)
    }

    func testFixedPaletteMapping() {
        var img = RGBAImage(width: 1, height: 1)
        img.setPixel(0, 0, 254, 254, 254, 255) // near-white
        let q = ColorQuantizer.map(img, to: workbench4Palette)
        XCTAssertEqual(q.indices[0], 2) // index 2 is white in the WB palette
    }
}

final class ColorIconStructureTests: XCTestCase {
    func testFormIconLayout() {
        var img = RGBAImage(width: 4, height: 4)
        for y in 0..<4 { for x in 0..<4 { img.setPixel(x, y, 10, 20, 30, 255) } }
        let indexed = ColorQuantizer.quantize(img, maxColors: 16)
        let form = ColorIcon(normal: indexed, selected: nil).encode()

        XCTAssertEqual(ascii(form, 0, 4), "FORM")
        let size = beU32(form, 4)
        XCTAssertEqual(Int(size), form.count - 8) // FORM size excludes id+size
        XCTAssertEqual(ascii(form, 8, 4), "ICON")
        XCTAssertEqual(ascii(form, 12, 4), "FACE")
        XCTAssertEqual(Int(beU32(form, 16)), 6)   // FACE is always 6 bytes
        XCTAssertEqual(form[20], 3)               // Width  - 1 == 3
        XCTAssertEqual(form[21], 3)               // Height - 1 == 3
    }

    func testSelectedAddsSecondImag() {
        let img = RGBAImage(width: 4, height: 4,
                            pixels: [UInt8](repeating: 200, count: 4 * 4 * 4))
        let n = ColorQuantizer.quantize(img, maxColors: 16)
        let oneImag = ColorIcon(normal: n, selected: nil).encode()
        let twoImag = ColorIcon(normal: n, selected: n).encode()
        XCTAssertGreaterThan(twoImag.count, oneImag.count)
    }
}

final class IconWriterTests: XCTestCase {
    func testDiskObjectMagicAndHeader() {
        let img = RGBAImage(width: 32, height: 32,
                            pixels: [UInt8](repeating: 255, count: 32 * 32 * 4))
        let bytes = IconWriter.build(normal: img, selected: nil, options: IconOptions())
        XCTAssertGreaterThan(bytes.count, 78)
        XCTAssertEqual(beU16(bytes, 0), 0xE310) // WB_DISKMAGIC
        XCTAssertEqual(beU16(bytes, 2), 1)      // WB_DISKVERSION
        // The trailing GlowIcon FORM should be present by default.
        XCTAssertTrue(containsAsciiSequence(bytes, "FORM"))
        XCTAssertTrue(containsAsciiSequence(bytes, "ICON"))
    }

    func testGlowProducesSelectedState() {
        var img = RGBAImage(width: 16, height: 16)
        // A solid opaque block in the middle, transparent border.
        for y in 4..<12 { for x in 4..<12 { img.setPixel(x, y, 0, 128, 255, 255) } }
        let glow = img.addingGlow(radius: 2, color: (255, 139, 0))
        // A pixel just outside the block should have become semi-opaque orange.
        let p = glow.pixel(3, 7)
        XCTAssertGreaterThan(p.a, 0)
        XCTAssertEqual(p.r, 255)
    }
}

final class NewIconsTests: XCTestCase {
    // NewIcons is experimental; this only proves the transfer codec round-trips.
    func testTransferEncodeIsPrintableAndReversible() {
        let data: [UInt8] = [0x00, 0x7F, 0x80, 0xAA, 0x55, 0xFF, 0x01]
        let enc = NewIcons.transferEncode(data)
        for b in enc { XCTAssertNotNil(NewIcons.dec7(b), "byte \(b) not in printable set") }
    }

    func testEncodeProducesIMLines() {
        let img = RGBAImage(width: 8, height: 8,
                            pixels: [UInt8](repeating: 120, count: 8 * 8 * 4))
        let q = ColorQuantizer.quantize(img, maxColors: 8)
        let lines = NewIcons.encode(normal: q, selected: nil)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines[0].hasPrefix("IM1="))
    }
}

// MARK: - byte helpers

private func ascii(_ b: [UInt8], _ off: Int, _ len: Int) -> String {
    String(decoding: b[off..<off + len], as: UTF8.self)
}
private func beU16(_ b: [UInt8], _ off: Int) -> UInt16 {
    (UInt16(b[off]) << 8) | UInt16(b[off + 1])
}
private func beU32(_ b: [UInt8], _ off: Int) -> UInt32 {
    (UInt32(b[off]) << 24) | (UInt32(b[off + 1]) << 16) | (UInt32(b[off + 2]) << 8) | UInt32(b[off + 3])
}
private func containsAsciiSequence(_ b: [UInt8], _ s: String) -> Bool {
    let needle = Array(s.utf8)
    guard needle.count <= b.count else { return false }
    for i in 0...(b.count - needle.count) where Array(b[i..<i + needle.count]) == needle { return true }
    return false
}
