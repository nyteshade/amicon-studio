#if os(macOS)
import SwiftUI
import AppKit
import AmigaIconKit

/// Edits the Workbench pen set for the planar fallback: pick a named preset as a
/// starting point, then tweak the exact pen RGBs, add/remove reserved pens, and
/// set the total colour count. Any edit turns the palette "Custom"; the exact
/// pens are stored with the project (per icon).
struct PaletteEditor: View {
    @Binding var palette: WorkbenchPalette

    private let columns = Array(repeating: GridItem(.flexible(minimum: 18), spacing: 4), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Palette", selection: presetBinding) {
                ForEach(WorkbenchPalette.presets) { Text($0.name).tag($0.id) }
                if palette.isCustom { Text("Custom").tag("custom") }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("PENS — \(palette.reservedCount) reserved")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { addPen() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .disabled(palette.systemPens.count >= WorkbenchPalette.maxPens)
                        .help("Add a reserved pen")
                    Button { removePen() } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                        .disabled(palette.systemPens.count <= 1)
                        .help("Remove the last reserved pen")
                }
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(palette.systemPens.indices, id: \.self) { i in
                        ColorPicker("", selection: penBinding(i), supportsOpacity: false)
                            .labelsHidden()
                            .help("Pen \(i)")
                    }
                }
            }

            Stepper("Total colours: \(palette.totalColors)",
                    value: totalColorsBinding, in: palette.reservedCount...256)
                .help("Pens above the reserved ones are generated from the artwork")
        }
    }

    // MARK: - Bindings (edits reconstruct the value type and mark it custom)

    private var presetBinding: Binding<String> {
        Binding(
            get: { palette.isCustom ? "custom" : palette.id },
            set: { if let preset = WorkbenchPalette.preset(id: $0) { palette = preset } }
        )
    }

    private func penBinding(_ i: Int) -> Binding<Color> {
        Binding(
            get: { Self.color(palette.systemPens[i]) },
            set: { newColor in
                var pens = palette.systemPens
                guard pens.indices.contains(i) else { return }
                pens[i] = Self.rgb(newColor)
                palette = .custom(systemPens: pens, totalColors: palette.totalColors)
            }
        )
    }

    private var totalColorsBinding: Binding<Int> {
        Binding(
            get: { palette.totalColors },
            set: { palette = .custom(systemPens: palette.systemPens, totalColors: $0) }
        )
    }

    private func addPen() {
        var pens = palette.systemPens
        pens.append(RGB(0, 0, 0))
        palette = .custom(systemPens: pens, totalColors: max(pens.count, palette.totalColors))
    }

    private func removePen() {
        var pens = palette.systemPens
        guard pens.count > 1 else { return }
        pens.removeLast()
        palette = .custom(systemPens: pens, totalColors: max(pens.count, palette.totalColors))
    }

    // MARK: - RGB <-> Color

    private static func color(_ c: RGB) -> Color {
        Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    private static func rgb(_ color: Color) -> RGB {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        return RGB(UInt8((ns.redComponent * 255).rounded()),
                   UInt8((ns.greenComponent * 255).rounded()),
                   UInt8((ns.blueComponent * 255).rounded()))
    }
}
#endif
