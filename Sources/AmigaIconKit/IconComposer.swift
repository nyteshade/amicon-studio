import Foundation

/// How artwork is scaled into the icon's content box.
public enum FitMode: String, Codable, CaseIterable, Equatable {
    case fit     // scale to fit inside, preserving aspect (letterbox)
    case fill    // scale to cover, preserving aspect (crop overflow)
    case stretch // scale X and Y independently to fill (may distort)
}

public extension RGBAImage {
    /// Fits the artwork into a `width × height` canvas, leaving `margin` px of
    /// transparent space on every side (room for glow / outline / shadow), using
    /// the given fit `mode`. Art is centred; `.fill` crops the overflow at the
    /// canvas edge. This is how the kit supports arbitrary (incl. non-square)
    /// Amiga icon sizes.
    func fitted(width: Int, height: Int, margin: Int = 0,
                mode: FitMode = .fit, filter: ResampleFilter = .smooth) -> RGBAImage {
        let outW = max(1, width), outH = max(1, height)
        let cw = max(1, outW - 2 * margin), ch = max(1, outH - 2 * margin)
        let nw: Int, nh: Int
        switch mode {
        case .stretch:
            nw = cw; nh = ch
        case .fit:
            let s = min(Double(cw) / Double(self.width), Double(ch) / Double(self.height))
            nw = max(1, Int((Double(self.width) * s).rounded()))
            nh = max(1, Int((Double(self.height) * s).rounded()))
        case .fill:
            let s = max(Double(cw) / Double(self.width), Double(ch) / Double(self.height))
            nw = max(1, Int((Double(self.width) * s).rounded()))
            nh = max(1, Int((Double(self.height) * s).rounded()))
        }
        let scaled = resized(to: nw, to: nh, filter: filter)
        var out = RGBAImage(width: outW, height: outH)
        let ox = (outW - nw) / 2, oy = (outH - nh) / 2
        for y in 0..<nh {
            let dy = oy + y
            guard dy >= 0, dy < outH else { continue }
            for x in 0..<nw {
                let dx = ox + x
                guard dx >= 0, dx < outW else { continue }
                let p = scaled.pixel(x, y)
                out.setPixel(dx, dy, p.r, p.g, p.b, p.a)
            }
        }
        return out
    }
}
