import XCTest
@testable import AmigaIconKit

final class WorkbenchPaletteTests: XCTestCase {

    func testPresetShape() {
        XCTAssertEqual(WorkbenchPalette.workbench1_4.systemPens.count, 4)
        XCTAssertEqual(WorkbenchPalette.workbench1_4.depth, 2)
        XCTAssertEqual(WorkbenchPalette.magicWB_8.reservedCount, 8)
        XCTAssertEqual(WorkbenchPalette.magicWB_8.depth, 3)
        XCTAssertEqual(WorkbenchPalette.workbench32_16.totalColors, 16)
        XCTAssertEqual(WorkbenchPalette.workbench32_16.reservedCount, 8)
        XCTAssertEqual(WorkbenchPalette.workbench32_16.depth, 4)
        // OS 3.2 reserves the same first eight pens as MagicWB.
        XCTAssertEqual(WorkbenchPalette.workbench32_8.systemPens, magicWB8Palette)
    }

    func testResolveToleratesLegacyNames() {
        XCTAssertEqual(WorkbenchPalette.resolve("wb4"), .workbench2_4)
        XCTAssertEqual(WorkbenchPalette.resolve("magicwb8"), .magicWB_8)
        XCTAssertEqual(WorkbenchPalette.resolve("mwb.16"), .magicWB_16)
        XCTAssertEqual(WorkbenchPalette.resolve("nonsense"), .workbench2_4)
    }

    /// The reserved system pens must survive colour reduction unchanged and stay
    /// at the front; artwork colours go into the free pens above them.
    func testReservedPensPreservedAtFront() {
        var img = RGBAImage(width: 4, height: 4)
        for y in 0..<4 { for x in 0..<4 { img.setPixel(x, y, 255, 0, 0, 255) } } // pure red

        let q = ColorQuantizer.mapReserving(img, reserved: magicWB8Palette, totalColors: 16)
        XCTAssertEqual(Array(q.palette.prefix(8)), magicWB8Palette) // pens 0–7 intact
        XCTAssertLessThanOrEqual(q.palette.count, 16)
        // Red isn't a MagicWB pen, so it must land in a generated pen (index >= 8).
        XCTAssertGreaterThanOrEqual(q.indices[0], 8)
    }

    /// When no free budget remains (total == reserved), nothing is generated.
    func testNoFreeBudgetKeepsOnlyReserved() {
        var img = RGBAImage(width: 2, height: 2)
        for i in 0..<4 { img.setPixel(i % 2, i / 2, 10, 200, 10, 255) }
        let q = ColorQuantizer.mapReserving(img, reserved: workbench4Palette, totalColors: 4)
        XCTAssertEqual(q.palette, workbench4Palette)
    }

    /// A 16-colour planar build must declare depth 4 and round-trip its indices,
    /// with the reserved pens intact.
    func testReservedPlanarBuildRoundTrips() throws {
        var img = RGBAImage(width: 24, height: 24)
        for y in 0..<24 { for x in 0..<24 { img.setPixel(x, y, UInt8(x * 10 % 256), UInt8(y * 10 % 256), 90, 255) } }

        var opts = IconOptions()
        opts.planarPalette = .magicWB_16
        opts.writeColorIcon = false // isolate the planar image

        let bytes = try IconWriter.build(normal: img, selected: nil, options: opts)
        let decoded = try IconDecoder.decode(bytes)

        XCTAssertEqual(decoded.planarNormal.depth, 4)
        XCTAssertEqual(decoded.planarNormal.indices.count,
                       decoded.planarNormal.width * decoded.planarNormal.height)
        // Indices stay within the 16-pen range.
        XCTAssertLessThan(decoded.planarNormal.indices.max() ?? 0, 16)
    }

    // MARK: - Custom palettes

    func testCustomFactory() {
        let p = WorkbenchPalette.custom(systemPens: [RGB(1, 2, 3), RGB(4, 5, 6)], totalColors: 8)
        XCTAssertTrue(p.isCustom)
        XCTAssertEqual(p.reservedCount, 2)
        XCTAssertEqual(p.totalColors, 8)
        XCTAssertEqual(p.depth, 3)
        XCTAssertFalse(WorkbenchPalette.magicWB_8.isCustom)
    }

    /// A custom palette must survive Codable round-tripping (it is stored in the
    /// project document).
    func testPaletteCodableRoundTrip() throws {
        let p = WorkbenchPalette.custom(systemPens: [RGB(10, 20, 30), RGB(200, 0, 0)], totalColors: 16)
        let back = try JSONDecoder().decode(WorkbenchPalette.self,
                                            from: try JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertTrue(back.isCustom)
        XCTAssertEqual(back.systemPens, [RGB(10, 20, 30), RGB(200, 0, 0)])
    }

    /// A custom pen set drives the planar reduction in a build.
    func testCustomPaletteUsedByBuild() throws {
        let red = RGB(255, 0, 0), green = RGB(0, 255, 0)
        var opts = IconOptions()
        opts.planarPalette = .custom(systemPens: [red, green], totalColors: 2)
        opts.writeColorIcon = false
        let img = RGBAImage(width: 8, height: 8, pixels: { var p = [UInt8](repeating: 0, count: 8 * 8 * 4)
            for i in 0..<(8 * 8) { p[i * 4] = 255; p[i * 4 + 3] = 255 }; return p }()) // all opaque red

        let decoded = try IconDecoder.decode(try IconWriter.build(normal: img, selected: nil, options: opts))
        XCTAssertEqual(decoded.planarNormal.depth, 1) // two pens -> 1 bitplane
        let rgba = decoded.planarNormal.rgba(palette: [red, green])
        XCTAssertEqual(rgba.pixel(0, 0).r, 255)
        XCTAssertEqual(rgba.pixel(0, 0).g, 0)
    }

    /// WB 1.x uses its own four pens, distinct from the grey 2.x set.
    func testWorkbench1IsDistinct() {
        XCTAssertNotEqual(WorkbenchPalette.workbench1_4.systemPens, workbench4Palette)
        XCTAssertEqual(WorkbenchPalette.workbench1_4.systemPens.first, RGB(0x00, 0x55, 0xAA))
    }
}
