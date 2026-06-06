#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AmigaIconKit

/// A drag-and-drop target ("bucket") for a single source image. Accepts PNG,
/// JPEG, TIFF, HEIC and anything else macOS can decode, plus drops from Finder
/// (file URLs) and other apps (image data). Whatever is dropped is normalised
/// to PNG at full resolution and stored via `pngData`.
struct DropWell: View {
    let title: String
    @Binding var pngData: Data?
    /// Optional already-composed preview (e.g. the glowing clicked state). When
    /// present it is shown instead of the raw dropped image.
    var preview: NSImage? = nil
    var size: CGFloat = 132
    @State private var targeted = false

    private var displayImage: NSImage? {
        if let preview { return preview }
        if let d = pngData { return NSImage(data: d) }
        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                CheckerboardBackground()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.08, style: .continuous))
                if let img = displayImage {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(size * 0.06)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: size * 0.22))
                            .foregroundStyle(.secondary)
                        Text("Drop image").font(.caption).foregroundStyle(.secondary)
                    }
                }
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: targeted ? 2.5 : 1, dash: [6]))
            }
            .frame(width: size, height: size)
            .onDrop(of: [.fileURL, .image, .png, .tiff, .jpeg],
                    isTargeted: $targeted, perform: handleDrop)

            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                if pngData != nil {
                    Button { pngData = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .help("Clear")
                }
            }
            .frame(width: size)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Prefer a file URL: gives us the original file's bytes.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let url, let data = try? Data(contentsOf: url) { store(rawImageData: data) }
            }
            return true
        }

        // Otherwise accept raw image data from another application.
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage, let tiff = img.tiffRepresentation {
                    store(rawImageData: tiff)
                }
            }
            return true
        }
        return false
    }

    /// Decodes any supported format and re-encodes to PNG at full resolution,
    /// preserving the original (so larger sizes can be re-rendered later).
    private func store(rawImageData data: Data) {
        let png = RGBAImage(data: data)?.pngData() ?? data
        DispatchQueue.main.async { pngData = png }
    }
}

/// A light/grey checkerboard, the conventional way to show image transparency.
struct CheckerboardBackground: View {
    var square: CGFloat = 8
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(size.width / square) + 1
            let rows = Int(size.height / square) + 1
            for r in 0..<rows {
                for c in 0..<cols where (r + c).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(c) * square, y: CGFloat(r) * square,
                                      width: square, height: square)
                    ctx.fill(Path(rect), with: .color(.secondary.opacity(0.18)))
                }
            }
        }
        .background(Color(white: 0.95))
    }
}
#endif
