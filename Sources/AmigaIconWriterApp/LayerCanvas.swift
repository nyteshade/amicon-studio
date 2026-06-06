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
    @State private var renamingID: UUID?
    @State private var dragAnchor: (id: UUID, x: Double, y: Double)?
    @State private var pickingSymbol = false
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
            .contextMenu { canvasMenu } // right-click empty canvas
        }
        .frame(width: size, height: size)
        .onDrop(of: [.fileURL, .image, .png, .tiff, .jpeg], isTargeted: nil, perform: handleDrop)
        .modifier(ScrollWheelHandler { adjustSelectedScale(by: $0) }) // scroll = resize selected
    }

    @ViewBuilder private var canvasMenu: some View {
        Button { addViaPanel() } label: { Label("Add Layer…", systemImage: "plus") }
        if selection != nil { Button("Deselect") { selection = nil } }
    }

    /// The context menu for a layer (shared by the canvas overlay and the list).
    @ViewBuilder private func layerMenu(_ l: Layer) -> some View {
        Button("Rename") { selection = l.id; renamingID = l.id }
        Button(l.visible ? "Hide" : "Show") { setVisible(l.id, !l.visible) }
        Button("Duplicate") { duplicate(l.id) }
        Divider()
        Button("Bring to Front") { bringToFront(l.id) }
        Button("Bring Forward") { move(byID: l.id, 1) }
        Button("Send Backward") { move(byID: l.id, -1) }
        Button("Send to Back") { sendToBack(l.id) }
        Divider()
        Button("Reset Position & Size") { mutate(l.id) { $0.x = 0.5; $0.y = 0.5; $0.scale = 0.4 } }
        Menu("Blend") {
            ForEach(LayerBlendMode.allCases, id: \.self) { m in
                Button(m.rawValue.capitalized) { setBlend(l.id, m) }
            }
        }
        Menu("Applies To") {
            ForEach(EffectTarget.allCases) { t in Button(t.label) { setTarget(l.id, t) } }
        }
        Divider()
        Button("Delete", role: .destructive) { item.layers.removeAll { $0.id == l.id }; selection = nil }
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
                    if dragAnchor?.id != l.id { dragAnchor = (l.id, l.x, l.y) }
                    var nx = min(1, max(0, (v.location.x - rect.minX) / rect.width))
                    var ny = min(1, max(0, (v.location.y - rect.minY) / rect.height))
                    if NSEvent.modifierFlags.contains(.shift), let a = dragAnchor {
                        if abs(nx - a.x) >= abs(ny - a.y) { ny = a.y } else { nx = a.x } // lock to an axis
                    }
                    layer.wrappedValue.x = nx; layer.wrappedValue.y = ny
                }.onEnded { _ in dragAnchor = nil })
                .onTapGesture { selection = l.id }
                .contextMenu { layerMenu(l) }

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
            Button { pickingSymbol = true } label: { Label("Add Symbol", systemImage: "star") }
            Button(role: .destructive) { removeSelected() } label: { Label("Remove", systemImage: "trash") }
                .disabled(selection == nil)
            Spacer()
            Text("\(item.layers.count) layer\(item.layers.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: size)
        .sheet(isPresented: $pickingSymbol) {
            SymbolPicker { data, name in
                let png = RGBAImage(data: data)?.pngData() ?? data
                var l = Layer(png: png); l.name = name; l.x = 0.5; l.y = 0.5
                item.layers.append(l); selection = l.id
            }
        }
    }

    @ViewBuilder
    private func inspector(for layer: Binding<Layer>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: layer.name).textFieldStyle(.roundedBorder)
            HStack { Text("Opacity").font(.caption); Slider(value: layer.opacity, in: 0...1) }
            HStack { Text("Size").font(.caption); Slider(value: layer.scale, in: 0.05...2) }
            Picker("Blend", selection: layer.blend) {
                ForEach(LayerBlendMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
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
                    if let thumb = NSImage(data: l.png) {
                        Image(nsImage: thumb).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)))
                            .opacity(l.visible ? 1 : 0.4)
                    }
                    if renamingID == l.id {
                        TextField("Name", text: $item.layers[idx].name)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 130)
                            .onSubmit { renamingID = nil }
                    } else {
                        Text(l.name).lineLimit(1)
                            .onTapGesture(count: 2) { selection = l.id; renamingID = l.id }
                    }
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
                .contextMenu { layerMenu(l) }
            }
        }
        .frame(width: size)
    }

    // MARK: - Mutations

    private func setVisible(_ id: UUID, _ v: Bool) { mutate(id) { $0.visible = v } }
    private func setBlend(_ id: UUID, _ m: LayerBlendMode) { mutate(id) { $0.blend = m } }
    private func setTarget(_ id: UUID, _ t: EffectTarget) { mutate(id) { $0.target = t } }
    private func mutate(_ id: UUID, _ change: (inout Layer) -> Void) {
        guard let i = item.layers.firstIndex(where: { $0.id == id }) else { return }
        change(&item.layers[i])
    }

    private func duplicate(_ id: UUID) {
        guard let i = item.layers.firstIndex(where: { $0.id == id }) else { return }
        var copy = item.layers[i]
        copy.id = UUID(); copy.name += " copy"
        copy.x = min(1, copy.x + 0.04); copy.y = min(1, copy.y + 0.04)
        item.layers.insert(copy, at: i + 1)
        selection = copy.id
    }

    private func move(byID id: UUID, _ delta: Int) {
        guard let i = item.layers.firstIndex(where: { $0.id == id }) else { return }
        move(i, by: delta)
    }
    private func bringToFront(_ id: UUID) {
        guard let i = item.layers.firstIndex(where: { $0.id == id }) else { return }
        let l = item.layers.remove(at: i); item.layers.append(l)
    }
    private func sendToBack(_ id: UUID) {
        guard let i = item.layers.firstIndex(where: { $0.id == id }) else { return }
        let l = item.layers.remove(at: i); item.layers.insert(l, at: 0)
    }

    private func adjustSelectedScale(by deltaY: CGFloat) {
        guard let i = selectedIndex else { return }
        item.layers[i].scale = min(2, max(0.05, item.layers[i].scale + Double(deltaY) * 0.003))
    }

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

/// Reports scroll-wheel deltas while the pointer is over the modified view, via a
/// local event monitor — so it doesn't interfere with SwiftUI's drag/click
/// gestures. Used to resize the selected layer with the scroll wheel.
private struct ScrollWheelHandler: ViewModifier {
    let onScroll: (CGFloat) -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, monitor == nil {
                    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                        onScroll(event.scrollingDeltaY)
                        return nil // consume while over the canvas
                    }
                } else if !inside { removeMonitor() }
            }
            .onDisappear(perform: removeMonitor)
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
#endif
