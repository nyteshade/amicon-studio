#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AmigaIconKit

struct ContentView: View {
    @Binding var document: IconProjectDocument
    @State private var selection: UUID?

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
                Button(action: addIcon) { Label("Add Icon", systemImage: "plus") }
                Button(action: importImages) { Label("Import Images", systemImage: "photo.badge.plus") }
                Button(action: importInfo) { Label("Import .info", systemImage: "square.and.arrow.down") }
                Button(action: exportSelected) { Label("Export .info", systemImage: "square.and.arrow.up") }
                    .disabled(selectedItemBinding == nil)
                Button(action: exportAll) { Label("Export All", systemImage: "square.and.arrow.up.on.square") }
                    .disabled(document.project.items.isEmpty)
            }
        }
        .onAppear { if selection == nil { selection = document.project.items.first?.id } }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Name", text: item.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)

                    effectsPalette(item)
                    effectStack(item)
                    Divider()
                    OutputSettingsView(settings: item.settings)
                }
                .padding(12)
            }
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
        VStack(alignment: .leading, spacing: 6) {
            Text("EFFECTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 6) {
                ForEach(EffectKind.allCases) { kind in
                    Button {
                        item.wrappedValue.effects.append(EffectInstance(kind))
                    } label: {
                        Image(systemName: kind.systemImage)
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .help(kind.displayName)
                }
            }
        }
    }

    @ViewBuilder
    private func effectStack(_ item: Binding<IconItem>) -> some View {
        if !item.wrappedValue.effects.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("APPLIED").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(item.effects) { $fx in
                    EffectRow(fx: $fx) {
                        item.wrappedValue.effects.removeAll { $0.id == fx.id }
                    }
                }
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
        DisclosureGroup("Output Settings") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Type", selection: $settings.iconType) {
                    Text("Disk").tag(Int(IconType.disk.rawValue))
                    Text("Drawer").tag(Int(IconType.drawer.rawValue))
                    Text("Tool").tag(Int(IconType.tool.rawValue))
                    Text("Project").tag(Int(IconType.project.rawValue))
                    Text("Trashcan").tag(Int(IconType.garbage.rawValue))
                    Text("AppIcon").tag(Int(IconType.appIcon.rawValue))
                }

                Group {
                    Text("GlowIcon (OS3.5+, 24-bit)").font(.caption.weight(.semibold))
                    Toggle("Write ColorIcon", isOn: $settings.writeColorIcon)
                    Stepper("Canvas: \(settings.colorCanvas)px", value: $settings.colorCanvas, in: 8...256)
                    Stepper("Artwork: \(settings.colorContent)px", value: $settings.colorContent, in: 8...256)
                    Stepper("Max colours: \(settings.maxColors)", value: $settings.maxColors, in: 2...256, step: 2)
                    Toggle("RLE compress", isOn: $settings.compress)
                    Toggle("Preserve aspect (non-square)", isOn: $settings.preserveAspect)
                    Stepper(settings.posterizeLevels < 2 ? "Posterize: off"
                            : "Posterize: \(settings.posterizeLevels) levels",
                            value: $settings.posterizeLevels, in: 0...32)
                }

                Group {
                    Text("Clicked-state glow").font(.caption.weight(.semibold))
                    Toggle("Auto-generate glow", isOn: $settings.autoGlow)
                    Stepper("Glow radius: \(settings.glowRadius)px", value: $settings.glowRadius, in: 1...16)
                    ColorPicker("Glow colour", selection: glowColorBinding, supportsOpacity: false)
                }

                Group {
                    Text("Outline").font(.caption.weight(.semibold))
                    Stepper("Thickness: \(settings.outlineThickness)px", value: $settings.outlineThickness, in: 0...16)
                    if settings.outlineThickness > 0 {
                        ColorPicker("Outline colour", selection: hexColorBinding(\.outlineColorHex),
                                    supportsOpacity: false)
                    }
                }

                Group {
                    Text("Shadows").font(.caption.weight(.semibold))
                    ShadowsEditor(shadows: $settings.shadows)
                }

                Group {
                    Text("Planar (OS1–3 fallback)").font(.caption.weight(.semibold))
                    Stepper("Canvas: \(settings.planarCanvas)px", value: $settings.planarCanvas, in: 8...256)
                    Stepper("Artwork: \(settings.planarContent)px", value: $settings.planarContent, in: 8...256)
                    PaletteEditor(palette: $settings.palette)
                    Toggle("Dither (Floyd–Steinberg)", isOn: Binding(
                        get: { settings.planarDither == .floydSteinberg },
                        set: { settings.planarDither = $0 ? .floydSteinberg : .none }))
                }

                Group {
                    Text("Scaling").font(.caption.weight(.semibold))
                    Picker("Resample", selection: $settings.resample) {
                        Text("Smooth (photos)").tag(ResampleFilter.smooth)
                        Text("Nearest (pixel art)").tag(ResampleFilter.nearest)
                    }
                }

                Group {
                    Text("Metadata").font(.caption.weight(.semibold))
                    TextField("Default tool", text: $settings.defaultTool)
                        .textFieldStyle(.roundedBorder)
                    ToolTypesEditor(toolTypes: $settings.toolTypes)
                }

                Toggle("NewIcons (experimental)", isOn: $settings.writeNewIcons)
            }
            .padding(.top, 6)
        }
        .font(.callout)
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
                    if s.kind == .outer {
                        Stepper("Blur \(s.blur)px", value: $s.blur, in: 0...12)
                    }
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

    var body: some View {
        if let item {
            let previews = IconRenderer.previews(for: item.wrappedValue)
            VStack(spacing: 16) {
                Text(item.wrappedValue.name).font(.title2.weight(.semibold))
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
                    Text("Badges — drag to move, drag the handle to resize")
                        .font(.caption).foregroundStyle(.secondary)
                    BadgeCanvas(item: item, background: NSImage(data: npng))
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
        "\(settings.planarCanvas)×\(settings.planarCanvas) · \(settings.palette.name)"
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
