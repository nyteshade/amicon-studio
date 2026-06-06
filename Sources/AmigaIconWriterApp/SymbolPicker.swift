#if os(macOS)
import SwiftUI
import AppKit

/// Searchable SF Symbol picker. Pick a symbol (tinted with a colour, or in its
/// intrinsic multicolor), and it's rasterised to a PNG and handed back to add as
/// a layer. Accepts any exact symbol name typed in the field, not just the
/// curated list.
struct SymbolPicker: View {
    let onPick: (Data, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var multicolor = false
    @State private var tint = Color.primary

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var names = q.isEmpty ? Array(SFSymbols.names.prefix(160)) : SFSymbols.names.filter { $0.contains(q) }
        if !q.isEmpty, NSImage(systemSymbolName: q, accessibilityDescription: nil) != nil, !names.contains(q) {
            names.insert(q, at: 0)
        }
        return Array(names.prefix(400))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search symbols (e.g. star, gearshape, bolt) — or type an exact name",
                          text: $query).textFieldStyle(.roundedBorder)
            }
            HStack {
                Toggle("Multicolor", isOn: $multicolor)
                if !multicolor { ColorPicker("Tint", selection: $tint, supportsOpacity: false) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(matches, id: \.self) { name in
                        if let preview = previewImage(name) {
                            Button { pick(name) } label: {
                                Image(nsImage: preview).resizable().scaledToFit().frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain).help(name)
                        }
                    }
                }
                .padding(4)
            }
        }
        .padding(12)
        .frame(width: 540, height: 480)
    }

    private func configuration(pointSize: CGFloat) -> NSImage.SymbolConfiguration {
        let base = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return multicolor ? base.applying(.preferringMulticolor())
                          : base.applying(.init(hierarchicalColor: NSColor(tint)))
    }

    private func previewImage(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration(pointSize: 22))
    }

    private func pick(_ name: String) {
        if let data = SymbolRasterizer.png(name: name, configuration: configuration(pointSize: 256)) {
            onPick(data, name)
        }
        dismiss()
    }
}

/// Renders a configured SF Symbol to PNG `Data` (with its colours baked in).
enum SymbolRasterizer {
    static func png(name: String, configuration: NSImage.SymbolConfiguration) -> Data? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let w = max(1, Int(img.size.width.rounded())), h = max(1, Int(img.size.height.rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = img.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: img.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
