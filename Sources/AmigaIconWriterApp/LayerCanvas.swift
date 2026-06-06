#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AmigaIconKit
import AmigaIconImageIO

/// Direct-manipulation layer editor: shows the source artwork and lets you drag
/// layers to position them and drag a corner handle (or scroll) to resize.
/// An inspector edits the selected layer's opacity, blend mode, size, target and
/// visibility; the composited result appears in the preview wells above.
struct LayerCanvas: View {
    @Binding var item: IconItem
    /// Source artwork shown as the backdrop (layers are live overlays).
    let background: NSImage?
    var size: CGFloat = 260

    @State private var selection: UUID?
    private let space = "layerCanvas"

    private var selectedIndex: Int? { item.layers.firstIndex { $0.id == selection } }

    var body: some View {
        VStack(spacing: 8) {
            canvas
            controls
            if let i = selectedIndex { inspector(for: $item.layers[i]) }
            layerList
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let rect = Self.fittedRect(imageSize: background?.size ?? CGSize(width: 1, height: 1), in: geo.size)
            ZStack(alignment: .topLeading) {
                CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                if let bg = background {
                    Image(nsImage: bg).resizable().interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                ForEach($item.layers) { $layer in overlay($layer, rect: rect) }
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
            }
            .coordinateSpace(name: space)
            .contentShape(Rectangle())
            .onTapGesture { selection = nil }
        }
        .frame(width: size, height: size)
        .onDrop(of: [.fileURL, .image, .png, .tiff, .jpeg], isTargeted: nil, perform: handleDrop)
    }

    @ViewBuilder
    private func overlay(_ layer: Binding<Layer>, rect: CGRect) -> some View {
        let l = layer.wrappedValue
        if l.visible, let img = NSImage(data: l.png) {
            let minSide = min(rect.width, rect.height)
            let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1
            let longer = max(10, l.scale * minSide)
            let w = aspect >= 1 ? longer : longer * aspect
            let h = aspect >= 1 ? longer / aspect : longer
            let center = CGPoint(x: rect.minX + l.x * rect.width, y: rect.minY + l.y * rect.height)
            let selected = selection == l.id

            Image(nsImage: img).resizable().interpolation(.high)
                .opacity(l.opacity)
                .frame(width: w, height: h)
                .overlay(selected ? RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: 1.5) : nil)
                .position(center)
                .gesture(DragGesture(coordinateSpace: .named(space)).onChanged { v in
                    selection = l.id
                    layer.wrappedValue.x = min(1, max(0, (v.location.x - rect.minX) / rect.width))
                    layer.wrappedValue.y = min(1, max(0, (v.location.y - rect.minY) / rect.height))
                })
                .onTapGesture { selection = l.id }

            if selected {
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                    .position(x: center.x + w / 2, y: center.y + h / 2)
                    .gesture(DragGesture(coordinateSpace: .named(space)).onChanged { v in
                        let d = 2 * max(abs(v.location.x - center.x), abs(v.location.y - center.y))
                        layer.wrappedValue.scale = min(2, max(0.05, d / minSide))
                    })
            }
        }
    }

    // MARK: - Controls, inspector, list

    private var controls: some View {
        HStack(spacing: 8) {
            Button { addViaPanel() } label: { Label("Add Layer", systemImage: "plus") }
            Button(role: .destructive) { removeSelected() } label: { Label("Remove", systemImage: "trash") }
                .disabled(selection == nil)
            Spacer()
            Text("\(item.layers.count) layer\(item.layers.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: size)
    }

    @ViewBuilder
    private func inspector(for layer: Binding<Layer>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: layer.name).textFieldStyle(.roundedBorder)
            HStack { Text("Opacity").font(.caption); Slider(value: layer.opacity, in: 0...1) }
            HStack { Text("Size").font(.caption); Slider(value: layer.scale, in: 0.05...2) }
            Picker("Blend", selection: layer.blend) {
                ForEach(BlendMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Applies to", selection: layer.target) {
                ForEach(EffectTarget.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Visible", isOn: layer.visible)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .frame(width: size)
    }

    private var layerList: some View {
        VStack(spacing: 2) {
            ForEach(Array(item.layers.enumerated()), id: \.element.id) { idx, l in
                HStack(spacing: 6) {
                    Button { item.layers[idx].visible.toggle() } label: {
                        Image(systemName: l.visible ? "eye" : "eye.slash")
                    }.buttonStyle(.borderless)
                    Text(l.name).lineLimit(1)
                    Spacer()
                    Button { move(idx, by: -1) } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderless).disabled(idx == 0)
                    Button { move(idx, by: 1) } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(.borderless).disabled(idx == item.layers.count - 1)
                }
                .padding(.vertical, 2).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(l.id == selection ? Color.accentColor.opacity(0.18) : Color.clear))
                .contentShape(Rectangle())
                .onTapGesture { selection = l.id }
            }
        }
        .frame(width: size)
    }

    // MARK: - Mutations

    private func move(_ idx: Int, by delta: Int) {
        let j = idx + delta
        guard item.layers.indices.contains(idx), item.layers.indices.contains(j) else { return }
        item.layers.swapAt(idx, j)
    }

    private func removeSelected() {
        item.layers.removeAll { $0.id == selection }
        selection = nil
    }

    private func addViaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let data = try? Data(contentsOf: url) { addLayer(rawImageData: data, name: url.deletingPathExtension().lastPathComponent) }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { it, _ in
                var url: URL?
                if let d = it as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = it as? URL { url = u }
                if let url, let data = try? Data(contentsOf: url) {
                    addLayer(rawImageData: data, name: url.deletingPathExtension().lastPathComponent)
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage, let tiff = img.tiffRepresentation { addLayer(rawImageData: tiff, name: "Layer") }
            }
            return true
        }
        return false
    }

    private func addLayer(rawImageData data: Data, name: String) {
        let png = RGBAImage(data: data)?.pngData() ?? data
        DispatchQueue.main.async {
            var l = Layer(png: png)
            l.name = name; l.x = 0.5; l.y = 0.5
            item.layers.append(l)
            selection = l.id
        }
    }

    static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: container) }
        let s = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * s, h = imageSize.height * s
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
#endif
