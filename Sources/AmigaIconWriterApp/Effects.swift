#if os(macOS)
import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// A CoreImage effect the user can stack onto a source image from the sidebar.
/// Parameters are intentionally generic (`amount` + `radius`) so the inspector
/// can drive every effect with one or two sliders.
enum EffectKind: String, Codable, CaseIterable, Identifiable {
    case brightness, contrast, saturation, hue, sepia, monochrome, invert, bloom, sharpen, vignette

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brightness: return "Brightness"
        case .contrast:   return "Contrast"
        case .saturation: return "Saturation"
        case .hue:        return "Hue Rotate"
        case .sepia:      return "Sepia"
        case .monochrome: return "Monochrome"
        case .invert:     return "Invert"
        case .bloom:      return "Bloom"
        case .sharpen:    return "Sharpen"
        case .vignette:   return "Vignette"
        }
    }

    var systemImage: String {
        switch self {
        case .brightness: return "sun.max"
        case .contrast:   return "circle.lefthalf.filled"
        case .saturation: return "drop"
        case .hue:        return "paintpalette"
        case .sepia:      return "camera.filters"
        case .monochrome: return "circle.grid.cross"
        case .invert:     return "circle.righthalf.filled"
        case .bloom:      return "sparkles"
        case .sharpen:    return "triangle"
        case .vignette:   return "smallcircle.filled.circle"
        }
    }

    /// Whether the inspector should expose the secondary `radius` slider.
    var usesRadius: Bool { self == .bloom || self == .sharpen || self == .vignette }

    var amountRange: ClosedRange<Double> {
        switch self {
        case .brightness: return -1...1
        case .contrast:   return 0...2
        case .saturation: return 0...2
        case .hue:        return -Double.pi...Double.pi
        case .sepia, .monochrome, .bloom, .vignette: return 0...1
        case .sharpen:    return 0...2
        case .invert:     return 0...1
        }
    }

    var defaultAmount: Double {
        switch self {
        case .brightness: return 0
        case .contrast, .saturation: return 1
        case .hue: return 0
        case .sepia, .monochrome, .bloom, .vignette: return 0.5
        case .sharpen: return 0.4
        case .invert: return 1
        }
    }

    var defaultRadius: Double { self == .sharpen ? 2 : 8 }
}

/// Which icon state(s) an effect applies to.
enum EffectTarget: String, Codable, CaseIterable, Identifiable {
    case both, unclicked, clicked
    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return "Both"
        case .unclicked: return "Unclicked"
        case .clicked: return "Clicked"
        }
    }
}

/// A configured, toggleable instance of an effect in an item's stack.
struct EffectInstance: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: EffectKind
    var amount: Double
    var radius: Double
    var enabled = true
    /// Which state(s) this effect filters (default both).
    var target: EffectTarget = .both

    init(_ kind: EffectKind) {
        self.kind = kind
        self.amount = kind.defaultAmount
        self.radius = kind.defaultRadius
    }
}

/// Applies a stack of effects to a `CIImage`, in order.
enum EffectPipeline {
    static func apply(_ effects: [EffectInstance], to input: CIImage) -> CIImage {
        var image = input
        for fx in effects where fx.enabled {
            image = apply(fx, to: image) ?? image
        }
        return image
    }

    private static func apply(_ fx: EffectInstance, to image: CIImage) -> CIImage? {
        switch fx.kind {
        case .brightness:
            let f = CIFilter.colorControls(); f.inputImage = image
            f.brightness = Float(fx.amount); return f.outputImage
        case .contrast:
            let f = CIFilter.colorControls(); f.inputImage = image
            f.contrast = Float(fx.amount); return f.outputImage
        case .saturation:
            let f = CIFilter.colorControls(); f.inputImage = image
            f.saturation = Float(fx.amount); return f.outputImage
        case .hue:
            let f = CIFilter.hueAdjust(); f.inputImage = image
            f.angle = Float(fx.amount); return f.outputImage
        case .sepia:
            let f = CIFilter.sepiaTone(); f.inputImage = image
            f.intensity = Float(fx.amount); return f.outputImage
        case .monochrome:
            let f = CIFilter.colorMonochrome(); f.inputImage = image
            f.color = CIColor(red: 0.6, green: 0.6, blue: 0.6)
            f.intensity = Float(fx.amount); return f.outputImage
        case .invert:
            let f = CIFilter.colorInvert(); f.inputImage = image; return f.outputImage
        case .bloom:
            let f = CIFilter.bloom(); f.inputImage = image
            f.radius = Float(fx.radius); f.intensity = Float(fx.amount)
            // Bloom expands extent; crop back so the canvas size is preserved.
            return f.outputImage?.cropped(to: image.extent)
        case .sharpen:
            let f = CIFilter.sharpenLuminance(); f.inputImage = image
            f.sharpness = Float(fx.amount); f.radius = Float(fx.radius); return f.outputImage
        case .vignette:
            let f = CIFilter.vignette(); f.inputImage = image
            f.intensity = Float(fx.amount); f.radius = Float(fx.radius); return f.outputImage
        }
    }
}
#endif
