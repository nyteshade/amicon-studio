import XCTest
@testable import AmigaIconKit

/// Round-trip tests: the bytes the encoder produces must decode back to exactly
/// the same pixels, palettes and metadata. These are the tests that actually
/// prove the format code is correct (the structure tests only check offsets).
final class IconDecoderTests: XCTestCase {

    // MARK: - ColorIcon (GlowIcon) codec

    /// A hand-built indexed image must survive ColorIcon encode → decode intact
    /// (RLE-compressed path).
    func testColorIconFormRoundTripCompressed() {
        let indexed = sampleIndexed(withTransparency: true)
        let form = ColorIcon(normal: indexed, selected: nil, compress: true).encode()
        let decoded = try! IconDecoder.decodeColorIconForm(form)
        XCTAssertEqual(decoded.normal, indexed)
        XCTAssertNil(decoded.selected)
    }

    /// Same, uncompressed (ImageFormat/PaletteFormat == 0).
    func testColorIconFormRoundTripRaw() {
        let indexed = sampleIndexed(withTransparency: true)
        let form = ColorIcon(normal: indexed, selected: nil, compress: false).encode()
        let decoded = try! IconDecoder.decodeColorIconForm(form)
        XCTAssertEqual(decoded.normal, indexed)
    }

    /// Two images (normal + selected) round-trip independently.
    func testColorIconTwoImagesRoundTrip() {
        let normal = sampleIndexed(withTransparency: true)
        let selected = sampleIndexed(withTransparency: false)
        let form = ColorIcon(normal: normal, selected: selected).encode()
        let decoded = try! IconDecoder.decodeColorIconForm(form)
        XCTAssertEqual(decoded.normal, normal)
        XCTAssertEqual(decoded.selected, selected)
    }

    // MARK: - Classic planar Image block

    func testPlanarImageBlockRoundTrip() {
        let indexed = sampleIndexed(withTransparency: false) // 5 colours -> depth 3
        let depth = indexed.depth
        var w = BinaryWriter()
        PlanarImage(indexed, depth: depth).write(into: &w)

        let decoded = try! IconDecoder.decodeImageBlock(w.data)
        XCTAssertEqual(decoded.width, indexed.width)
        XCTAssertEqual(decoded.height, indexed.height)
        XCTAssertEqual(decoded.depth, depth)
        XCTAssertEqual(decoded.indices, indexed.indices)
    }

    /// Row padding: a width that is not a multiple of 16 exercises the word
    /// alignment in both the writer and the reader.
    func testPlanarRoundTripOddWidth() {
        var img = RGBAImage(width: 13, height: 7)
        for y in 0..<7 { for x in 0..<13 { img.setPixel(x, y, UInt8(x * 17), UInt8(y * 31), 0, 255) } }
        let indexed = ColorQuantizer.map(img, to: magicWB8Palette)
        let depth = 3
        var w = BinaryWriter()
        PlanarImage(indexed, depth: depth).write(into: &w)
        let decoded = try! IconDecoder.decodeImageBlock(w.data)
        XCTAssertEqual(decoded.indices, indexed.indices)
    }

    // MARK: - Full .info file

    func testFullInfoRoundTrip() {
        var img = RGBAImage(width: 24, height: 24)
        for y in 0..<24 { for x in 0..<24 { img.setPixel(x, y, UInt8(x * 10), UInt8(y * 10), 64, 255) } }

        var opts = IconOptions()
        opts.type = .tool
        opts.defaultTool = "SYS:Utilities/MultiView"
        opts.toolTypes = ["FOO=bar", "BAZ=qux"]

        let bytes = IconWriter.build(normal: img, selected: nil, options: opts)
        let decoded = try! IconDecoder.decode(bytes)

        XCTAssertEqual(decoded.rawType, IconType.tool.rawValue)
        XCTAssertEqual(decoded.type, .tool)
        XCTAssertEqual(decoded.defaultTool, "SYS:Utilities/MultiView")
        XCTAssertEqual(decoded.toolTypes, ["FOO=bar", "BAZ=qux"])
        XCTAssertTrue(decoded.hasColorIcon)
        // autoGlow is on by default, so a selected ColorIcon state is generated.
        XCTAssertNotNil(decoded.colorIconSelected)
        // Planar fallback is always present; no explicit selected -> none.
        XCTAssertGreaterThan(decoded.planarNormal.width, 0)
        XCTAssertNil(decoded.planarSelected)
    }

    /// The decoded GlowIcon must reproduce exactly what the quantiser produced —
    /// the heart of the "accurate preview" guarantee.
    func testColorIconMatchesQuantizerOutput() {
        var img = RGBAImage(width: 20, height: 20)
        for y in 0..<20 { for x in 0..<20 { img.setPixel(x, y, UInt8(x * 12 % 256), 30, 200, 255) } }

        var opts = IconOptions()
        opts.autoGlow = false // isolate the normal image

        let bytes = IconWriter.build(normal: img, selected: nil, options: opts)
        let decoded = try! IconDecoder.decode(bytes)

        let composed = img.centered(inCanvas: opts.colorCanvasSize, contentSize: opts.colorContentSize)
        let expected = ColorQuantizer.quantize(composed, maxColors: opts.colorMaxColors)

        XCTAssertEqual(decoded.colorIconNormal, expected)
        XCTAssertNil(decoded.colorIconSelected)
    }

    /// An explicit selected image is written to both the planar and color paths.
    func testExplicitSelectedRoundTrips() {
        let normal = RGBAImage(width: 16, height: 16, pixels: [UInt8](repeating: 200, count: 16 * 16 * 4))
        let selected = RGBAImage(width: 16, height: 16, pixels: [UInt8](repeating: 90, count: 16 * 16 * 4))
        let bytes = IconWriter.build(normal: normal, selected: selected, options: IconOptions())
        let decoded = try! IconDecoder.decode(bytes)
        XCTAssertNotNil(decoded.planarSelected)
        XCTAssertNotNil(decoded.colorIconSelected)
    }

    func testBadMagicThrows() {
        XCTAssertThrowsError(try IconDecoder.decode([0x00, 0x00, 0x00, 0x00, 0x00, 0x00])) { error in
            guard case IconDecoder.DecodeError.badMagic = error else {
                return XCTFail("expected badMagic, got \(error)")
            }
        }
    }

    func testTruncatedThrows() {
        // Valid magic then nothing — must throw, not crash.
        XCTAssertThrowsError(try IconDecoder.decode([0xE3, 0x10, 0x00, 0x01]))
    }

    // MARK: - Helpers

    /// A small indexed image with a known palette and a deterministic index
    /// pattern; optionally reserves a transparent index.
    private func sampleIndexed(withTransparency: Bool) -> IndexedImage {
        let w = 6, h = 5
        var palette = [RGB(10, 20, 30), RGB(200, 0, 0), RGB(0, 200, 0), RGB(0, 0, 200), RGB(255, 255, 0)]
        let transparentIndex: Int?
        if withTransparency {
            transparentIndex = palette.count
            palette.append(RGB(0, 0, 0))
        } else {
            transparentIndex = nil
        }
        var indices = [Int](repeating: 0, count: w * h)
        for i in 0..<(w * h) { indices[i] = i % palette.count }
        return IndexedImage(width: w, height: h, indices: indices,
                            palette: palette, transparentIndex: transparentIndex)
    }
}
