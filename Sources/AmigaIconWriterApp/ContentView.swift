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
                }

                Group {
                    Text("Clicked-state glow").font(.caption.weight(.semibold))
                    Toggle("Auto-generate glow", isOn: $settings.autoGlow)
                    Stepper("Glow radius: \(settings.glowRadius)px", value: $settings.glowRadius, in: 1...16)
                    ColorPicker("Glow colour", selection: glowColorBinding, supportsOpacity: false)
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
