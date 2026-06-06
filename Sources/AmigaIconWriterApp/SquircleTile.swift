#if os(macOS)
import SwiftUI
import AppKit

/// A bottom-strip thumbnail for one project icon.
///
/// The *tile* is a macOS-style squircle (a continuous-curvature rounded
/// rectangle) — that rounding is just a presentation container. The Amiga icon
/// artwork drawn inside keeps its own arbitrary shape and transparency and is
/// **not** clipped to the squircle.
struct SquircleTile: View {
    let item: IconItem
    let isSelected: Bool
    var size: CGFloat = 72

    private var thumbnail: NSImage? { IconRenderer.previews(for: item).normal }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Squircle container chrome.
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                          lineWidth: isSelected ? 2.5 : 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

                // The actual icon art — unclipped, retains its real shape.
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(size * 0.14)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)

            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: size)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}
#endif
