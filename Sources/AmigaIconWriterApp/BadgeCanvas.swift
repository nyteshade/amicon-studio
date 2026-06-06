#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AmigaIconKit
import AmigaIconImageIO

/// Direct-manipulation badge editor: shows the source artwork and lets you drag
/// badges to position them and drag a corner handle to resize. Add by dropping
/// images (or the Add button); the composited result appears in the preview
/// wells above. Positions/sizes are stored normalised on each `Badge`.
struct BadgeCanvas: View {
    @Binding var item: IconItem
    /// The source artwork shown as the backdrop (badges are live overlays).
    let background: NSImage?
    var size: CGFloat = 240

    @State private var selection: UUID?
    private let space = "badgeCanvas"

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let rect = Self.fittedRect(imageSize: background?.size ?? CGSize(width: 1, height: 1),
                                           in: geo.size)
                ZStack(alignment: .topLeading) {
                    CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if let bg = background {
                        Image(nsImage: bg).resizable().interpolation(.high)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                    ForEach($item.badges) { $badge in
                        badgeOverlay($badge, rect: rect)
                    }
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                }
                .coordinateSpace(name: space)
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }
            }
            .frame(width: size, height: size)
            .onDrop(of: [.fileURL, .image, .png, .tiff, .jpeg], isTargeted: nil, perform: handleDrop)

            HStack(spacing: 8) {
                Button { addViaPanel() } label: { Label("Add Badge", systemImage: "plus") }
                Button(role: .destructive) { removeSelected() } label: { Label("Remove", systemImage: "trash") }
                    .disabled(selection == nil)
                Spacer()
                Text("\(item.badges.count) badge\(item.badges.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: size)
        }
    }

    // MARK: - One badge

    @ViewBuilder
    private func badgeOverlay(_ badge: Binding<Badge>, rect: CGRect) -> some View {
        let b = badge.wrappedValue
        if let img = NSImage(data: b.png) {
            let minSide = min(rect.width, rect.height)
            let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1
            let longer = max(10, b.scale * minSide)
            let w = aspect >= 1 ? longer : longer * aspect
            let h = aspect >= 1 ? longer / aspect : longer
            let center = CGPoint(x: rect.minX + b.x * rect.width, y: rect.minY + b.y * rect.height)
            let selected = selection == b.id

            // The badge image (drag to move).
            Image(nsImage: img).resizable().interpolation(.high)
                .frame(width: w, height: h)
                .overlay(selected ? RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5) : nil)
                .position(center)
                .gesture(DragGesture(coordinateSpace: .named(space)).onChanged { v in
                    selection = b.id
                    badge.wrappedValue.x = min(1, max(0, (v.location.x - rect.minX) / rect.width))
                    badge.wrappedValue.y = min(1, max(0, (v.location.y - rect.minY) / rect.height))
                })
                .onTapGesture { selection = b.id }

            // Resize handle at the badge's bottom-right corner (drag to scale).
            if selected {
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                    .position(x: center.x + w / 2, y: center.y + h / 2)
                    .gesture(DragGesture(coordinateSpace: .named(space)).onChanged { v in
                        let dx = abs(v.location.x - center.x), dy = abs(v.location.y - center.y)
                        let newLonger = 2 * max(dx, dy)
                        badge.wrappedValue.scale = min(2.0, max(0.05, newLonger / minSide))
                    })
            }
        }
    }

    // MARK: - Add / remove

    private func removeSelected() {
        item.badges.removeAll { $0.id == selection }
        selection = nil
    }

    private func addViaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let data = try? Data(contentsOf: url) { addBadge(rawImageData: data) }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { it, _ in
                var url: URL?
                if let d = it as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = it as? URL { url = u }
                if let url, let data = try? Data(contentsOf: url) { addBadge(rawImageData: data) }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage, let tiff = img.tiffRepresentation { addBadge(rawImageData: tiff) }
            }
            return true
        }
        return false
    }

    /// Normalises any dropped/added image to PNG and appends it centred.
    private func addBadge(rawImageData data: Data) {
        let png = RGBAImage(data: data)?.pngData() ?? data
        DispatchQueue.main.async {
            var b = Badge(png: png)
            b.x = 0.5; b.y = 0.5
            item.badges.append(b)
            selection = b.id
        }
    }

    // MARK: - Geometry

    /// The aspect-fit rect for `imageSize` centred in `container`.
    static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: container) }
        let s = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * s, h = imageSize.height * s
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
#endif
