#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AmigaIconKit

struct ContentView: View {
    @Binding var document: IconProjectDocument
    @State private var selection: UUID?
    @StateObject private var history = UndoHistory()

    var body: some View {
        HStack(spacing: 0) {
            ToolSidebar(item: selectedItemBinding)
                .frame(width: 248)
            Divider()
            VStack(spacing: 0) {
                IconCanvas(item: selectedItemBinding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                BottomStrip(items: $document.project.items,
                            selection: $selection,
                            addIcon: addIcon,
                            deleteSelected: deleteSelected)
                    .frame(height: 132)
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .toolbar {
            ToolbarItemGroup {
                Button { var p = document.project; history.undo(&p); document.project = p } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!history.canUndo).keyboardShortcut("z", modifiers: .command)
                Button { var p = document.project; history.redo(&p); document.project = p } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!history.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
                Divider()
                Button(action: addIcon) { Label("Add Icon", systemImage: "plus") }
                Button(action: importImages) { Label("Import Images", systemImage: "photo.badge.plus") }
                Button(action: importInfo) { Label("Import .info", systemImage: "square.and.arrow.down") }
                Button(action: exportSelected) { Label("Export .info", systemImage: "square.and.arrow.up") }
                    .disabled(selectedItemBinding == nil)
                Button(action: exportPNG) { Label("Export PNG", systemImage: "photo") }
                    .disabled(selectedItemBinding == nil)
                Button(action: exportAll) { Label("Export All", systemImage: "square.and.arrow.up.on.square") }
                    .disabled(document.project.items.isEmpty)
            }
        }
        .onAppear {
            if selection == nil { selection = document.project.items.first?.id }
            history.sync(document.project)
        }
        .onChange(of: document.project) { newValue in history.sync(newValue) }
    }

    // MARK: - Selection plumbing

    private var selectedItemBinding: Binding<IconItem>? {
        guard let id = selection,
              let idx = document.project.items.firstIndex(where: { $0.id == id }) else { return nil }
        return $document.project.items[idx]
    }

    private func addIcon() {
        var item = IconItem()
        item.name = "Icon \(document.project.items.count + 1)"
        document.project.items.append(item)
        selection = item.id
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        document.project.items.removeAll { $0.id == id }
        selection = document.project.items.first?.id
    }

    // MARK: - Import images (files or whole folders)

    private func importImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.message = "Choose images or a folder of images to add as icons."
        panel.allowedContentTypes = [.image, .folder]
        guard panel.runModal() == .OK else { return }

        // Expand any chosen folders into their top-level image files.
        var files: [URL] = []
        for url in panel.urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil)) ?? []
                files += contents.filter(isImageFile).sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else {
                files.append(url)
            }
        }
        for url in files {
            guard let data = try? Data(contentsOf: url),
                  let item = IconRenderer.item(fromImage: data,
                                               name: url.deletingPathExtension().lastPathComponent) else { continue }
            document.project.items.append(item)
            selection = item.id
        }
    }

    private func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image)
    }

    // MARK: - Import existing .info icons

    private func importInfo() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "info") ?? .data]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url),
                  let item = IconRenderer.item(fromInfo: data,
                                               name: url.deletingPathExtension().lastPathComponent) else { continue }
            document.project.items.append(item)
            selection = item.id
        }
    }

    // MARK: - Export

    private func exportSelected() {
        guard let item = selectedItemBinding?.wrappedValue,
              let data = IconRenderer.infoData(for: item) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sanitized(item.name) + ".info"
        panel.allowedContentTypes = [UTType(filenameExtension: "info") ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func exportPNG() {
        guard let item = selectedItemBinding?.wrappedValue,
              let png = IconRenderer.compositePNG(for: item, clicked: false) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sanitized(item.name) + ".png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url { try? png.write(to: url) }
    }

    private func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        for item in document.project.items {
            guard let data = IconRenderer.infoData(for: item) else { continue }
            let url = dir.appendingPathComponent(sanitized(item.name) + ".info")
            try? data.write(to: url)
        }
    }

    private func sanitized(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: bad).joined(separator: "_")
        return cleaned.isEmpty ? "Icon" : cleaned
    }
}

// MARK: - Leading tool sidebar

struct ToolSidebar: View {
    let item: Binding<IconItem>?

    var body: some View {
        if let item {
            Form {
                Section("Icon") {
                    TextField("Name", text: item.name)
                }
                Section("Effects") {
                    effectsPalette(item)
                    effectStack(item)
                }
                OutputSettingsView(settings: item.settings)
            }
            .formStyle(.grouped)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "square.dashed").font(.largeTitle).foregroundStyle(.secondary)
                Text("Add or select an icon").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func effectsPalette(_ item: Binding<IconItem>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 6) {
            ForEach(EffectKind.allCases) { kind in
                Button {
                    item.wrappedValue.effects.append(EffectInstance(kind))
                } label: {
                    Image(systemName: kind.systemImage).frame(width: 34, height: 30)
                }
                .buttonStyle(.bordered)
                .help(kind.displayName)
            }
        }
    }

    @ViewBuilder
    private func effectStack(_ item: Binding<IconItem>) -> some View {
        ForEach(item.effects) { $fx in
            EffectRow(fx: $fx) {
                item.wrappedValue.effects.removeAll { $0.id == fx.id }
            }
        }
    }
}

struct EffectRow: View {
    @Binding var fx: EffectInstance
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(isOn: $fx.enabled) {
                    Label(fx.kind.displayName, systemImage: fx.kind.systemImage)
                        .labelStyle(.titleAndIcon)
                }
                .toggleStyle(.checkbox)
                Spacer()
                Button(action: onRemove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            Slider(value: $fx.amount, in: fx.kind.amountRange)
            if fx.kind.usesRadius {
                Slider(value: $fx.radius, in: 0...20)
            }
            Picker("", selection: $fx.target) {
                ForEach(EffectTarget.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .opacity(fx.enabled ? 1 : 0.5)
    }
}

// MARK: - Output settings

struct OutputSettingsView: View {
    @Binding var settings: RenderSettings

    var body: some View {
        Group {
            Section("Icon type") {
                Picker("Type", selection: $settings.iconType) {
                    Text("Disk").tag(Int(IconType.disk.rawValue))
                    Text("Drawer").tag(Int(IconType.drawer.rawValue))
                    Text("Tool").tag(Int(IconType.tool.rawValue))
                    Text("Project").tag(Int(IconType.project.rawValue))
                    Text("Trashcan").tag(Int(IconType.garbage.rawValue))
                    Text("AppIcon").tag(Int(IconType.appIcon.rawValue))
                }
            }

            Section("GlowIcon (OS3.5+, 24-bit)") {
                Toggle("Write ColorIcon", isOn: $settings.writeColorIcon)
                Stepper("Width: \(settings.colorWidth) px", value: $settings.colorWidth, in: 8...256)
                Stepper("Height: \(settings.colorHeight) px", value: $settings.colorHeight, in: 8...256)
                Stepper("Margin: \(settings.colorMargin) px", value: $settings.colorMargin, in: 0...64)
                Picker("Fit", selection: $settings.fitMode) {
                    ForEach(FitMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Stepper("Max colours: \(settings.maxColors)", value: $settings.maxColors, in: 2...256, step: 2)
                Toggle("RLE compress", isOn: $settings.compress)
                Stepper(settings.posterizeLevels < 2 ? "Posterize: off"
                        : "Posterize: \(settings.posterizeLevels) levels",
                        value: $settings.posterizeLevels, in: 0...32)
            }

            Section("Clicked-state glow") {
                Toggle("Auto-generate glow", isOn: $settings.autoGlow)
                Stepper("Glow radius: \(settings.glowRadius) px", value: $settings.glowRadius, in: 1...16)
                ColorPicker("Glow colour", selection: glowColorBinding, supportsOpacity: false)
            }

            Section("Outline") {
                Stepper("Thickness: \(settings.outlineThickness) px", value: $settings.outlineThickness, in: 0...16)
                if settings.outlineThickness > 0 {
                    ColorPicker("Outline colour", selection: hexColorBinding(\.outlineColorHex), supportsOpacity: false)
                }
            }

            Section("Orientation & adjust") {
                HStack {
                    Toggle("Flip H", isOn: $settings.flipH).toggleStyle(.button)
                    Toggle("Flip V", isOn: $settings.flipV).toggleStyle(.button)
                    Button { settings.rotateQuarters = (settings.rotateQuarters + 1) % 4 } label: {
                        Label("\(settings.rotateQuarters * 90)°", systemImage: "rotate.right")
                    }
                }
                Stepper("Blur: \(settings.blurRadius) px", value: $settings.blurRadius, in: 0...12)
                LabeledContent("Tint") {
                    HStack {
                        ColorPicker("", selection: hexColorBinding(\.tintColorHex), supportsOpacity: false).labelsHidden()
                        Slider(value: $settings.tintAmount, in: 0...1)
                    }
                }
            }

            Section("Shadows") { ShadowsEditor(shadows: $settings.shadows) }

            Section("Planar (OS1–3 fallback)") {
                Stepper("Width: \(settings.planarWidth) px", value: $settings.planarWidth, in: 8...256)
                Stepper("Height: \(settings.planarHeight) px", value: $settings.planarHeight, in: 8...256)
                Stepper("Margin: \(settings.planarMargin) px", value: $settings.planarMargin, in: 0...64)
                PaletteEditor(palette: $settings.palette)
                Toggle("Dither (Floyd–Steinberg)", isOn: Binding(
                    get: { settings.planarDither == .floydSteinberg },
                    set: { settings.planarDither = $0 ? .floydSteinberg : .none }))
            }

            Section("Scaling") {
                Picker("Resample", selection: $settings.resample) {
                    Text("Smooth (photos)").tag(ResampleFilter.smooth)
                    Text("Nearest (pixel art)").tag(ResampleFilter.nearest)
                }
            }

            Section("Metadata") {
                TextField("Default tool", text: $settings.defaultTool)
                ToolTypesEditor(toolTypes: $settings.toolTypes)
                Toggle("NewIcons (experimental)", isOn: $settings.writeNewIcons)
            }
        }
    }

    private var glowColorBinding: Binding<Color> {
        Binding(
            get: {
                if let rgb = RGB(hex: settings.glowColorHex) {
                    return Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
                }
                return .orange
            },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.deviceRGB) ?? .orange
                let rgb = RGB(UInt8(ns.redComponent * 255), UInt8(ns.greenComponent * 255), UInt8(ns.blueComponent * 255))
                settings.glowColorHex = rgb.hexString
            }
        )
    }

    /// A `Color` binding backed by a `RRGGBB` hex string field on the settings.
    private func hexColorBinding(_ keyPath: WritableKeyPath<RenderSettings, String>) -> Binding<Color> {
        Binding(
            get: {
                if let rgb = RGB(hex: settings[keyPath: keyPath]) {
                    return Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
                }
                return .black
            },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.deviceRGB) ?? .black
                settings[keyPath: keyPath] = RGB(UInt8(ns.redComponent * 255),
                                                 UInt8(ns.greenComponent * 255),
                                                 UInt8(ns.blueComponent * 255)).hexString
            }
        )
    }
}

/// Editable list of shadows (outer/inner), each with offset, colour and opacity.
struct ShadowsEditor: View {
    @Binding var shadows: [Shadow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Drop & inner shadows").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { shadows.append(Shadow()) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add a shadow")
            }
            ForEach($shadows) { $s in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Picker("", selection: $s.kind) {
                            ForEach(Shadow.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        .labelsHidden().frame(width: 96)
                        Spacer()
                        ColorPicker("", selection: colorBinding($s), supportsOpacity: false).labelsHidden()
                        Button { shadows.removeAll { $0.id == s.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                    HStack {
                        Stepper("X \(s.dx)", value: $s.dx, in: -16...16)
                        Stepper("Y \(s.dy)", value: $s.dy, in: -16...16)
                    }
                    Stepper("Blur \(s.blur)px", value: $s.blur, in: 0...12)
                    HStack { Text("Opacity").font(.caption); Slider(value: alphaBinding($s), in: 0...1) }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
            }
        }
    }

    private func colorBinding(_ s: Binding<Shadow>) -> Binding<Color> {
        Binding(
            get: { let c = s.wrappedValue.color
                   return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255) },
            set: { let ns = NSColor($0).usingColorSpace(.deviceRGB) ?? .black
                   s.wrappedValue.color = RGB(UInt8(ns.redComponent * 255),
                                              UInt8(ns.greenComponent * 255),
                                              UInt8(ns.blueComponent * 255)) }
        )
    }

    private func alphaBinding(_ s: Binding<Shadow>) -> Binding<Double> {
        Binding(get: { Double(s.wrappedValue.alpha) / 255 },
                set: { s.wrappedValue.alpha = UInt8(max(0, min(1, $0)) * 255) })
    }
}

/// An editable list of Amiga tool types (`KEY=VALUE` lines).
struct ToolTypesEditor: View {
    @Binding var toolTypes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("TOOL TYPES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { toolTypes.append("") } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add a tool type")
            }
            ForEach(toolTypes.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    TextField("KEY=VALUE", text: Binding(
                        get: { i < toolTypes.count ? toolTypes[i] : "" },
                        set: { if i < toolTypes.count { toolTypes[i] = $0 } }))
                        .textFieldStyle(.roundedBorder)
                    Button { if i < toolTypes.count { toolTypes.remove(at: i) } } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless).help("Remove")
                }
            }
        }
    }
}

// MARK: - The two-slot canvas

struct IconCanvas: View {
    let item: Binding<IconItem>?
    @State private var bypassEffects = false

    var body: some View {
        if let item {
            let previews = IconRenderer.previews(for: item.wrappedValue, bypassEffects: bypassEffects)
            VStack(spacing: 16) {
                Text(item.wrappedValue.name).font(.title2.weight(.semibold))
                if !item.wrappedValue.effects.isEmpty {
                    Toggle("Show original (bypass filters)", isOn: $bypassEffects)
                        .toggleStyle(.switch).font(.caption)
                }
                HStack(alignment: .top, spacing: 40) {
                    VStack {
                        DropWell(title: "Unclicked", pngData: item.normalPNG,
                                 preview: previews.normal, size: 220)
                        Text("Normal state").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack {
                        DropWell(title: "Clicked", pngData: item.clickedPNG,
                                 preview: previews.clicked, size: 220)
                        Text(item.wrappedValue.clickedPNG == nil && item.wrappedValue.settings.autoGlow
                             ? "Auto glow" : "Selected state")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let npng = item.wrappedValue.normalPNG {
                    Divider().frame(width: 360)
                    Text("Layers — drag to move, drag the handle to resize")
                        .font(.caption).foregroundStyle(.secondary)
                    LayerCanvas(item: item, background: NSImage(data: npng))
                }
                if let planar = previews.planar {
                    PlanarFallbackPreview(image: planar, settings: item.wrappedValue.settings)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("Drop images into a new icon to begin").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The classic OS1–3 planar fallback, shown crisp (no smoothing) so its small
/// size and limited palette read honestly. This is the image old Workbenches
/// render; the GlowIcon above is what OS3.5+ shows.
struct PlanarFallbackPreview: View {
    let image: NSImage
    let settings: RenderSettings

    private var caption: String {
        "\(settings.planarWidth)×\(settings.planarHeight) · \(settings.palette.name)"
    }

    var body: some View {
        VStack(spacing: 6) {
            Divider().frame(width: 220)
            Text("OS 1.x–3.x planar fallback")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ZStack {
                CheckerboardBackground()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(6)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
            }
            .frame(width: 96, height: 96)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bottom squircle strip

struct BottomStrip: View {
    @Binding var items: [IconItem]
    @Binding var selection: UUID?
    let addIcon: () -> Void
    let deleteSelected: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    SquircleTile(item: item, isSelected: item.id == selection)
                        .onTapGesture { selection = item.id }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                selection = item.id
                                deleteSelected()
                            }
                        }
                }
                Button(action: addIcon) {
                    RoundedRectangle(cornerRadius: 72 * 0.28, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .overlay(Image(systemName: "plus").font(.title).foregroundStyle(.secondary))
                        .frame(width: 72, height: 72)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
#endif
