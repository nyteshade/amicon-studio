import XCTest
@testable import AmigaIconKit

/// Tests for the colour-reduction quality features: area-averaging downscale and
/// Floyd–Steinberg dithering.
final class QualityTests: XCTestCase {

    // MARK: - Area-averaging resample

    /// Shrinking 2×2 distinct colours to 1×1 yields their average.
    func testAreaResampleDownscaleAverages() {
        var img = RGBAImage(width: 2, height: 2)
        img.setPixel(0, 0, 255, 0, 0, 255)
        img.setPixel(1, 0, 0, 255, 0, 255)
        img.setPixel(0, 1, 0, 0, 255, 255)
        img.setPixel(1, 1, 255, 255, 255, 255)
        let out = img.resized(to: 1, to: 1, filter: .smooth)
        let p = out.pixel(0, 0)
        XCTAssertEqual(Int(p.r), 128, accuracy: 2)
        XCTAssertEqual(Int(p.g), 128, accuracy: 2)
        XCTAssertEqual(Int(p.b), 128, accuracy: 2)
        XCTAssertEqual(p.a, 255)
    }

    /// Alpha-weighting: a transparent neighbour must not bleed its (black) colour
    /// into the averaged result, and the alpha is the mean coverage.
    func testAreaResampleAlphaWeightedNoHalo() {
        var img = RGBAImage(width: 2, height: 1)
        img.setPixel(0, 0, 200, 0, 0, 255) // opaque red
        img.setPixel(1, 0, 0, 0, 0, 0)     // fully transparent
        let out = img.resized(to: 1, to: 1, filter: .smooth)
        let p = out.pixel(0, 0)
        XCTAssertEqual(p.r, 200)          // colour comes only from the opaque pixel
        XCTAssertEqual(Int(p.a), 128, accuracy: 3) // ~50% coverage
    }

    func testSmoothUpscaleHasCorrectSize() {
        var img = RGBAImage(width: 2, height: 2)
        for i in 0..<4 { img.setPixel(i % 2, i / 2, 10, 20, 30, 255) }
        let out = img.resized(to: 4, to: 4, filter: .smooth)
        XCTAssertEqual(out.width, 4)
        XCTAssertEqual(out.height, 4)
    }

    func testNearestStillAvailable() {
        var img = RGBAImage(width: 2, height: 1)
        img.setPixel(0, 0, 10, 10, 10, 255)
        img.setPixel(1, 0, 250, 250, 250, 255)
        let out = img.resized(to: 1, to: 1, filter: .nearest)
        // Nearest picks an actual source pixel, never an average.
        let r = Int(out.pixel(0, 0).r)
        XCTAssertTrue(r == 10 || r == 250)
    }

    // MARK: - Floyd–Steinberg dithering

    /// Dithering never invents pens: every index stays within the palette.
    func testDitherKeepsIndicesInRange() {
        var img = RGBAImage(width: 16, height: 16)
        for y in 0..<16 { for x in 0..<16 { img.setPixel(x, y, UInt8(x * 16), UInt8(y * 16), 100, 255) } }
        let q = ColorQuantizer.map(img, to: workbench4Palette, dither: .floydSteinberg)
        XCTAssertEqual(q.palette, workbench4Palette)
        XCTAssertTrue(q.indices.allSatisfy { $0 >= 0 && $0 < workbench4Palette.count })
    }

    /// A flat colour that exactly matches a pen produces zero error, so dithering
    /// introduces no noise — every pixel maps to that one pen.
    func testDitherFlatExactColorNoNoise() {
        let white = RGBAImage(width: 8, height: 8,
                              pixels: [UInt8](repeating: 255, count: 8 * 8 * 4))
        let q = ColorQuantizer.map(white, to: workbench4Palette, dither: .floydSteinberg)
        let whiteIndex = workbench4Palette.firstIndex(of: RGB(0xFF, 0xFF, 0xFF))!
        XCTAssertTrue(q.indices.allSatisfy { $0 == whiteIndex })
    }

    /// On a smooth gradient, dithering must produce more pen variety than plain
    /// nearest snapping (that is the whole point).
    func testDitherAddsVarietyOnGradient() {
        var img = RGBAImage(width: 32, height: 4)
        for y in 0..<4 { for x in 0..<32 { let v = UInt8(x * 8); img.setPixel(x, y, v, v, v, 255) } }
        let plain = ColorQuantizer.map(img, to: workbench4Palette, dither: .none)
        let dithered = ColorQuantizer.map(img, to: workbench4Palette, dither: .floydSteinberg)
        // Count distinct pens used along the first row's transition region.
        func distinct(_ q: IndexedImage) -> Int { Set(q.indices).count }
        XCTAssertGreaterThanOrEqual(distinct(dithered), distinct(plain))
        XCTAssertNotEqual(plain.indices, dithered.indices)
    }

    /// Transparent pixels stay on the background pen and never receive error.
    func testDitherLeavesTransparentOnBackground() {
        var img = RGBAImage(width: 4, height: 4)
        for y in 0..<4 { for x in 0..<4 { img.setPixel(x, y, 0, 0, 0, 0) } } // all transparent
        let q = ColorQuantizer.map(img, to: workbench4Palette, backgroundIndex: 0, dither: .floydSteinberg)
        XCTAssertTrue(q.indices.allSatisfy { $0 == 0 })
    }

    // MARK: - Compositing (badge overlay)

    func testBlendingOpaqueReplaces() {
        let base = RGBAImage(width: 4, height: 4, pixels: { var p = [UInt8](repeating: 0, count: 4 * 4 * 4)
            for i in 0..<16 { p[i * 4] = 255; p[i * 4 + 3] = 255 }; return p }()) // opaque red
        var top = RGBAImage(width: 2, height: 2)
        for i in 0..<4 { top.setPixel(i % 2, i / 2, 0, 0, 255, 255) } // opaque blue
        let out = base.blending(top, atX: 1, atY: 1)
        XCTAssertEqual(out.pixel(1, 1).b, 255) // blue where stamped
        XCTAssertEqual(out.pixel(1, 1).r, 0)
        XCTAssertEqual(out.pixel(0, 0).r, 255) // red elsewhere
    }

    func testBlendingHalfAlphaMixes() {
        let base = RGBAImage(width: 1, height: 1, pixels: [255, 0, 0, 255]) // opaque red
        let top = RGBAImage(width: 1, height: 1, pixels: [0, 255, 0, 128])  // ~50% green
        let p = base.blending(top, atX: 0, atY: 0).pixel(0, 0)
        XCTAssertEqual(Int(p.r), 127, accuracy: 2)
        XCTAssertEqual(Int(p.g), 128, accuracy: 2)
        XCTAssertEqual(p.a, 255)
    }

    func testBlendingClipsOutOfBounds() {
        let base = RGBAImage(width: 2, height: 2, pixels: [UInt8](repeating: 255, count: 2 * 2 * 4))
        var top = RGBAImage(width: 2, height: 2)
        for i in 0..<4 { top.setPixel(i % 2, i / 2, 10, 10, 10, 255) } // opaque dark
        // Placed mostly off-canvas; only (1,1) overlaps — must not crash.
        let out = base.blending(top, atX: 1, atY: 1)
        XCTAssertEqual(out.width, 2)
        XCTAssertEqual(out.pixel(1, 1).r, 10)
        XCTAssertEqual(out.pixel(0, 0).r, 255) // untouched
    }

    func testOutlineSurroundsSilhouette() {
        var img = RGBAImage(width: 8, height: 8)   // transparent
        img.setPixel(4, 4, 255, 255, 255, 255)     // one opaque white pixel
        let o = img.outlined(color: (0, 0, 0), thickness: 1)
        XCTAssertEqual(o.pixel(3, 4).a, 255); XCTAssertEqual(o.pixel(3, 4).r, 0) // black outline
        XCTAssertEqual(o.pixel(5, 4).a, 255)
        XCTAssertEqual(o.pixel(4, 4).r, 255)        // original art untouched
        XCTAssertEqual(o.pixel(0, 0).a, 0)          // far pixel stays transparent
    }

    // MARK: - Non-square canvas (preserve aspect)

    /// A wide source with `preserveAspectRatio` yields a non-square canvas that
    /// hugs the artwork; both the GlowIcon and planar images are wider than tall.
    func testPreserveAspectProducesNonSquareCanvas() throws {
        var img = RGBAImage(width: 64, height: 16) // 4:1
        for y in 0..<16 { for x in 0..<64 { img.setPixel(x, y, 200, 100, 50, 255) } }
        var opts = IconOptions()
        opts.preserveAspectRatio = true
        let decoded = try IconDecoder.decode(try IconWriter.build(normal: img, selected: nil, options: opts))
        let c = decoded.colorIconNormal!
        XCTAssertGreaterThan(c.width, c.height)
        XCTAssertGreaterThan(decoded.planarNormal.width, decoded.planarNormal.height)
        XCTAssertNotNil(decoded.colorIconSelected) // glow still generated on the rectangle
    }

    /// Without the option, the canvas stays square regardless of source aspect.
    func testSquareCanvasByDefault() throws {
        var img = RGBAImage(width: 64, height: 16)
        for y in 0..<16 { for x in 0..<64 { img.setPixel(x, y, 200, 100, 50, 255) } }
        let decoded = try IconDecoder.decode(try IconWriter.build(normal: img, selected: nil, options: IconOptions()))
        let c = decoded.colorIconNormal!
        XCTAssertEqual(c.width, c.height)
    }

    /// End-to-end: a dithered planar build still round-trips through the decoder.
    func testDitheredPlanarBuildRoundTrips() throws {
        var img = RGBAImage(width: 30, height: 30)
        for y in 0..<30 { for x in 0..<30 { img.setPixel(x, y, UInt8(x * 8 % 256), UInt8(y * 8 % 256), 120, 255) } }
        var opts = IconOptions()
        opts.planarPalette = .magicWB_16
        opts.planarDither = .floydSteinberg
        opts.resampleFilter = .smooth
        opts.writeColorIcon = false

        let bytes = try IconWriter.build(normal: img, selected: nil, options: opts)
        let decoded = try IconDecoder.decode(bytes)
        XCTAssertEqual(decoded.planarNormal.depth, 4)
        XCTAssertLessThan(decoded.planarNormal.indices.max() ?? 0, 16)
    }
}
