#if os(macOS)
import Foundation

/// A curated, searchable set of common SF Symbol names. The full catalog isn't
/// enumerable via public API, so this is a representative list; the picker also
/// accepts any exact symbol name typed into the search field, and silently skips
/// names that don't resolve on this OS.
enum SFSymbols {
    static let names: [String] = [
        // General / UI
        "star", "star.fill", "heart", "heart.fill", "bolt", "bolt.fill", "flame", "flame.fill",
        "sparkles", "wand.and.stars", "crown", "crown.fill", "rosette", "seal", "seal.fill",
        "checkmark", "checkmark.circle", "checkmark.seal", "xmark", "xmark.circle", "plus",
        "plus.circle", "minus", "minus.circle", "questionmark.circle", "exclamationmark.triangle",
        "info.circle", "ellipsis", "ellipsis.circle", "line.3.horizontal", "magnifyingglass",
        // Files / tools
        "folder", "folder.fill", "doc", "doc.fill", "doc.text", "tray", "tray.fill", "archivebox",
        "shippingbox", "trash", "trash.fill", "paperclip", "link", "pencil", "pencil.tip",
        "paintbrush", "paintbrush.fill", "paintpalette", "eyedropper", "scissors", "ruler",
        "hammer", "wrench", "wrench.and.screwdriver", "screwdriver", "gear", "gearshape",
        "gearshape.fill", "gearshape.2", "slider.horizontal.3", "highlighter", "eraser",
        // People / comms
        "person", "person.fill", "person.2", "person.crop.circle", "person.3",
        "envelope", "envelope.fill", "paperplane", "paperplane.fill", "phone", "phone.fill",
        "message", "message.fill", "bubble.left", "bell", "bell.fill", "flag", "flag.fill",
        "bookmark", "bookmark.fill", "tag", "tag.fill",
        // Media / devices
        "play", "play.fill", "pause", "pause.fill", "stop", "stop.fill", "forward", "backward",
        "speaker.wave.2", "speaker.wave.3", "mic", "mic.fill", "music.note", "headphones",
        "camera", "camera.fill", "photo", "photo.fill", "video", "video.fill", "film", "tv",
        "gamecontroller", "gamecontroller.fill", "desktopcomputer", "laptopcomputer", "keyboard",
        "printer", "externaldrive", "internaldrive", "memorychip", "cpu", "display", "network",
        "wifi", "antenna.radiowaves.left.and.right", "battery.100", "powerplug", "terminal",
        // Nature / weather
        "sun.max", "sun.max.fill", "moon", "moon.fill", "moon.stars", "cloud", "cloud.fill",
        "cloud.rain", "cloud.bolt", "snowflake", "drop", "drop.fill", "leaf", "leaf.fill",
        "globe", "globe.americas.fill", "map", "mappin", "location", "location.fill",
        // Transport / commerce
        "car", "car.fill", "airplane", "bicycle", "bus", "tram", "ferry", "fuelpump",
        "cart", "cart.fill", "bag", "bag.fill", "creditcard", "banknote", "dollarsign.circle",
        "gift", "gift.fill",
        // Time / security
        "calendar", "clock", "clock.fill", "alarm", "timer", "stopwatch", "hourglass",
        "lock", "lock.fill", "lock.open", "key", "key.fill", "shield", "shield.fill",
        // Shapes / arrows
        "arrow.up", "arrow.down", "arrow.left", "arrow.right", "arrow.clockwise",
        "arrow.triangle.2.circlepath", "chevron.left", "chevron.right", "chevron.up", "chevron.down",
        "circle", "circle.fill", "square", "square.fill", "triangle", "triangle.fill",
        "hexagon", "hexagon.fill", "diamond", "diamond.fill", "square.grid.2x2",
        // Knowledge
        "lightbulb", "lightbulb.fill", "book", "book.fill", "books.vertical", "graduationcap",
        "atom", "function", "sum", "percent", "number",
    ]
}
#endif
