import Foundation

public extension RGBAImage {
    /// Scales the image (preserving aspect ratio) to fit within
    /// `contentSize × contentSize`, then centres it on a transparent
    /// `canvasSize × canvasSize` canvas.
    ///
    /// This is the standard GlowIcon layout: artwork at, say, 48×48 sitting in a
    /// 54×54 canvas, leaving a 3px margin all round for the selected-state glow
    /// to bloom into without being clipped.
    func centered(inCanvas canvasSize: Int, contentSize: Int) -> RGBAImage {
        let content = min(contentSize, canvasSize)
        let scale = min(Double(content) / Double(width), Double(content) / Double(height))
        let nw = max(1, Int((Double(width) * scale).rounded()))
        let nh = max(1, Int((Double(height) * scale).rounded()))
        let scaled = resized(to: nw, to: nh)

        var out = RGBAImage(width: canvasSize, height: canvasSize)
        let ox = (canvasSize - nw) / 2
        let oy = (canvasSize - nh) / 2
        for y in 0..<nh {
            for x in 0..<nw {
                let p = scaled.pixel(x, y)
                out.setPixel(ox + x, oy + y, p.r, p.g, p.b, p.a)
            }
        }
        return out
    }
}
