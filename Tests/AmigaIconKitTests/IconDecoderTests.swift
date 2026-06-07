import XCTest
@testable import AmigaIconKit

/// Round-trip tests: the bytes the encoder produces must decode back to exactly
/// the same pixels, palettes and metadata. These are the tests that actually
/// prove the format code is correct (the structure tests only check offsets).
final class IconDecoderTests: XCTestCase {

    // MARK: - ColorIcon (GlowIcon) codec

    /// A hand-built indexed image must survive ColorIcon encode → decode intact
    /// (RLE-compressed path).
    func testColorIconFormRoundTripCompressed() throws {
        let indexed = sampleIndexed(withTransparency: true)
        let form = try ColorIcon(normal: indexed, selected: nil, compress: true).encode()
        let decoded = try IconDecoder.decodeColorIconForm(form)
        XCTAssertEqual(decoded.normal, indexed)
        XCTAssertNil(decoded.selected)
    }

    /// Same, uncompressed (ImageFormat/PaletteFormat == 0).
    func testColorIconFormRoundTripRaw() throws {
        let indexed = sampleIndexed(withTransparency: true)
        let form = try ColorIcon(normal: indexed, selected: nil, compress: false).encode()
        let decoded = try IconDecoder.decodeColorIconForm(form)
        XCTAssertEqual(decoded.normal, indexed)
    }

    /// Two images (normal + selected) round-trip independently.
    func testColorIconTwoImagesRoundTrip() throws {
        let normal = sampleIndexed(withTransparency: true)
        let selected = sampleIndexed(withTransparency: false)
        let form = try ColorIcon(normal: normal, selected: selected).encode()
        let decoded = try IconDecoder.decodeColorIconForm(form)
        XCTAssertEqual(decoded.normal, normal)
        XCTAssertEqual(decoded.selected, selected)
    }

    // MARK: - Classic planar Image block

    func testPlanarImageBlockRoundTrip() throws {
        let indexed = sampleIndexed(withTransparency: false) // 5 colours -> depth 3
        let depth = indexed.depth
        var w = BinaryWriter()
        PlanarImage(indexed, depth: depth).write(into: &w)

        let decoded = try IconDecoder.decodeImageBlock(w.data)
        XCTAssertEqual(decoded.width, indexed.width)
        XCTAssertEqual(decoded.height, indexed.height)
        XCTAssertEqual(decoded.depth, depth)
        XCTAssertEqual(decoded.indices, indexed.indices)
    }

    /// Row padding: a width that is not a multiple of 16 exercises the word
    /// alignment in both the writer and the reader.
    func testPlanarRoundTripOddWidth() throws {
        var img = RGBAImage(width: 13, height: 7)
        for y in 0..<7 { for x in 0..<13 { img.setPixel(x, y, UInt8(x * 17), UInt8(y * 31), 0, 255) } }
        let indexed = ColorQuantizer.map(img, to: magicWB8Palette)
        let depth = 3
        var w = BinaryWriter()
        PlanarImage(indexed, depth: depth).write(into: &w)
        let decoded = try IconDecoder.decodeImageBlock(w.data)
        XCTAssertEqual(decoded.indices, indexed.indices)
    }

    // MARK: - Full .info file

    func testFullInfoRoundTrip() throws {
        var img = RGBAImage(width: 24, height: 24)
        for y in 0..<24 { for x in 0..<24 { img.setPixel(x, y, UInt8(x * 10), UInt8(y * 10), 64, 255) } }

        var opts = IconOptions()
        opts.type = .tool
        opts.defaultTool = "SYS:Utilities/MultiView"
        opts.toolTypes = ["FOO=bar", "BAZ=qux"]

        let bytes = try IconWriter.build(normal: img, selected: nil, options: opts)
        let decoded = try IconDecoder.decode(bytes)

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
    func testColorIconMatchesQuantizerOutput() throws {
        var img = RGBAImage(width: 20, height: 20)
        for y in 0..<20 { for x in 0..<20 { img.setPixel(x, y, UInt8(x * 12 % 256), 30, 200, 255) } }

        var opts = IconOptions()
        opts.autoGlow = false // isolate the normal image

        let bytes = try IconWriter.build(normal: img, selected: nil, options: opts)
        let decoded = try IconDecoder.decode(bytes)

        let composed = img.fitted(width: opts.colorWidth, height: opts.colorHeight,
                                  margin: opts.colorMargin, mode: opts.fitMode, filter: opts.resampleFilter)
        let expected = ColorQuantizer.quantize(composed, maxColors: opts.colorMaxColors)

        XCTAssertEqual(decoded.colorIconNormal, expected)
        XCTAssertNil(decoded.colorIconSelected)
    }

    /// An explicit selected image is written to both the planar and color paths.
    func testExplicitSelectedRoundTrips() throws {
        let normal = RGBAImage(width: 16, height: 16, pixels: [UInt8](repeating: 200, count: 16 * 16 * 4))
        let selected = RGBAImage(width: 16, height: 16, pixels: [UInt8](repeating: 90, count: 16 * 16 * 4))
        let bytes = try IconWriter.build(normal: normal, selected: selected, options: IconOptions())
        let decoded = try IconDecoder.decode(bytes)
        XCTAssertNotNil(decoded.planarSelected)
        XCTAssertNotNil(decoded.colorIconSelected)
    }

    /// Writing a built icon to disk and decoding it back must reproduce its
    /// metadata — and renders are available for re-editing an imported icon.
    func testFileRoundTripAndRenders() throws {
        var img = RGBAImage(width: 16, height: 16)
        for y in 0..<16 { for x in 0..<16 { img.setPixel(x, y, UInt8(x * 16), 80, UInt8(y * 16), 255) } }
        var opts = IconOptions()
        opts.type = .tool
        opts.toolTypes = ["A=1"]
        let bytes = try IconWriter.build(normal: img, selected: nil, options: opts)

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("amicon_sample.info")
        try Data(bytes).write(to: url)
        let decoded = try IconDecoder.decode([UInt8](Data(contentsOf: url)))

        XCTAssertEqual(decoded.type, .tool)
        XCTAssertTrue(decoded.hasColorIcon)
        // Re-editable renders: normal prefers the GlowIcon; selected exists (glow).
        XCTAssertEqual(decoded.renderedNormal().width, decoded.colorIconNormal?.width)
        XCTAssertNotNil(decoded.renderedSelected())
        XCTAssertFalse(decoded.summary.isEmpty)
    }

    /// With no GlowIcon, the rendered normal falls back to the planar image.
    func testRenderedNormalFallsBackToPlanar() throws {
        let img = RGBAImage(width: 16, height: 16, pixels: [UInt8](repeating: 200, count: 16 * 16 * 4))
        var opts = IconOptions()
        opts.writeColorIcon = false
        let decoded = try IconDecoder.decode(try IconWriter.build(normal: img, selected: nil, options: opts))
        XCTAssertNil(decoded.colorIconNormal)
        let r = decoded.renderedNormal(planarPalette: workbench4Palette)
        XCTAssertEqual(r.width, decoded.planarNormal.width)
    }

    /// A drawer icon's DrawerData window record must round-trip, and everything
    /// after it (images, tool types, GlowIcon) must still decode at the right
    /// offset (DrawerData adds 56 bytes before the images).
    func testDrawerDataRoundTrips() throws {
        let img = RGBAImage(width: 16, height: 16, pixels: [UInt8](repeating: 180, count: 16 * 16 * 4))
        var opts = IconOptions()
        opts.type = .drawer
        opts.toolTypes = ["WINDOW=open"]
        opts.drawerData = DrawerInfo(left: 64, top: 40, width: 320, height: 256, currentX: 8, currentY: 12)

        let decoded = try IconDecoder.decode(try IconWriter.build(normal: img, selected: nil, options: opts))
        XCTAssertEqual(decoded.type, .drawer)
        XCTAssertEqual(decoded.drawer,
                       DrawerInfo(left: 64, top: 40, width: 320, height: 256, currentX: 8, currentY: 12))
        XCTAssertEqual(decoded.toolTypes, ["WINDOW=open"]) // offset preserved past DrawerData
        XCTAssertTrue(decoded.hasColorIcon)
    }

    func testNoDrawerDataForToolIcons() throws {
        let img = RGBAImage(width: 16, height: 16, pixels: [UInt8](repeating: 180, count: 16 * 16 * 4))
        var opts = IconOptions(); opts.type = .tool
        let decoded = try IconDecoder.decode(try IconWriter.build(normal: img, selected: nil, options: opts))
        XCTAssertNil(decoded.drawer)
    }

    /// Decode → reencode → decode preserves images and metadata losslessly, and
    /// edits to the decoded struct carry through.
    func testReencodeRoundTripAndEdit() throws {
        var img = RGBAImage(width: 24, height: 24)
        for y in 0..<24 { for x in 0..<24 { img.setPixel(x, y, UInt8(x * 10), UInt8(y * 10), 70, 255) } }
        var opts = IconOptions(); opts.type = .tool; opts.toolTypes = ["A=1"]
        var decoded = try IconDecoder.decode(try IconWriter.build(normal: img, selected: nil, options: opts))

        // Edit metadata, then reencode.
        decoded.toolTypes = ["B=2", "C=3"]
        let re = try IconDecoder.decode(try IconWriter.reencode(decoded))

        XCTAssertEqual(re.type, .tool)
        XCTAssertEqual(re.toolTypes, ["B=2", "C=3"])               // edit carried through
        XCTAssertEqual(re.colorIconNormal, decoded.colorIconNormal) // images unchanged
        XCTAssertEqual(re.colorIconSelected, decoded.colorIconSelected)
        XCTAssertEqual(re.planarNormal.indices, decoded.planarNormal.indices)
        XCTAssertEqual(re.planarNormal.depth, decoded.planarNormal.depth)
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

    // MARK: - 16-bit format-limit handling

    /// A 256×256 image at 256 colours packs to exactly 65536 image bytes — the
    /// largest the format's 16-bit `NumImageBytes` field can express. This used
    /// to be silently clamped (corrupting the icon); it must now encode and
    /// round-trip exactly. The raw packing is chosen because RLE would expand it.
    func testLargeIconAtFormatLimitRoundTrips() throws {
        let w = 256, h = 256
        var palette: [RGB] = []
        for i in 0..<256 { palette.append(RGB(UInt8(i), UInt8((i * 7) % 256), UInt8((i * 13) % 256))) }
        var indices = [Int](repeating: 0, count: w * h)
        for i in 0..<(w * h) { indices[i] = i % 256 } // uses all 256 colours -> depth 8
        let img = IndexedImage(width: w, height: h, indices: indices,
                               palette: palette, transparentIndex: nil)

        let form = try ColorIcon(normal: img, selected: nil, compress: true).encode()
        let decoded = try IconDecoder.decodeColorIconForm(form)
        XCTAssertEqual(decoded.normal, img)
    }

    /// RLE that would expand the data must not be chosen over the raw packing.
    func testNoisyImagePrefersRawAndRoundTrips() throws {
        let w = 40, h = 40
        var palette: [RGB] = []
        for i in 0..<16 { palette.append(RGB(UInt8(i * 16), UInt8(255 - i * 16), UInt8(i * 8))) }
        var indices = [Int](repeating: 0, count: w * h)
        for i in 0..<(w * h) { indices[i] = (i * 7 + i / 3) % 16 } // high-entropy, RLE-hostile
        let img = IndexedImage(width: w, height: h, indices: indices,
                               palette: palette, transparentIndex: nil)

        let compressed = try ColorIcon(normal: img, selected: nil, compress: true).encode()
        let raw = try ColorIcon(normal: img, selected: nil, compress: false).encode()
        // "compress: true" should never be larger than the forced-raw form.
        XCTAssertLessThanOrEqual(compressed.count, raw.count)

        let decoded = try IconDecoder.decodeColorIconForm(compressed)
        XCTAssertEqual(decoded.normal, img)
    }

    func testDimensionTooLargeThrows() {
        let w = 300, h = 4 // 300 > 256 -> FACE width can't represent it
        let img = IndexedImage(width: w, height: h, indices: [Int](repeating: 0, count: w * h),
                               palette: [RGB(0, 0, 0), RGB(1, 1, 1)], transparentIndex: nil)
        XCTAssertThrowsError(try ColorIcon(normal: img).encode()) { error in
            guard case ColorIconError.dimensionTooLarge = error else {
                return XCTFail("expected dimensionTooLarge, got \(error)")
            }
        }
    }

    func testTooManyColorsThrows() {
        var palette: [RGB] = []
        for i in 0..<300 { palette.append(RGB(UInt8(i % 256), 0, 0)) } // 300 > 256
        let img = IndexedImage(width: 2, height: 2, indices: [0, 1, 2, 3],
                               palette: palette, transparentIndex: nil)
        XCTAssertThrowsError(try ColorIcon(normal: img).encode()) { error in
            guard case ColorIconError.tooManyColors = error else {
                return XCTFail("expected tooManyColors, got \(error)")
            }
        }
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
