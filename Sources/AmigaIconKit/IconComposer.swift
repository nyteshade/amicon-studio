import Foundation

public extension RGBAImage {
    /// Scales the image (preserving aspect ratio) to fit within
    /// `contentSize × contentSize`, then centres it on a transparent
    /// `canvasSize × canvasSize` canvas.
    ///
    /// This is the standard GlowIcon layout: artwork at, say, 48×48 sitting in a
    /// 54×54 canvas, leaving a 3px margin all round for the selected-state glow
    /// to bloom into without being clipped.
    func centered(inCanvas canvasSize: Int, contentSize: Int,
                  filter: ResampleFilter = .smooth) -> RGBAImage {
        let content = min(contentSize, canvasSize)
        let scale = min(Double(content) / Double(width), Double(content) / Double(height))
        let nw = max(1, Int((Double(width) * scale).rounded()))
        let nh = max(1, Int((Double(height) * scale).rounded()))
        let scaled = resized(to: nw, to: nh, filter: filter)

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

    /// Fits artwork into the icon canvas, optionally producing a **non-square**
    /// canvas that hugs the artwork's aspect ratio (as many classic Amiga icons
    /// do) instead of forcing a square.
    ///
    /// - With `preserveAspect == false` this is exactly `centered(inCanvas:
    ///   contentSize:)` — a square `maxCanvas × maxCanvas` canvas.
    /// - With `preserveAspect == true` the artwork is scaled to fit a
    ///   `maxContent` box (preserving aspect), then a uniform `(maxCanvas -
    ///   maxContent)/2` margin is added on every side — so the canvas is
    ///   `scaledW + 2·margin` by `scaledH + 2·margin`, leaving the same room for
    ///   the selected-state glow on all sides.
    func fitted(maxCanvas: Int, maxContent: Int,
                preserveAspect: Bool, filter: ResampleFilter = .smooth) -> RGBAImage {
        guard preserveAspect else {
            return centered(inCanvas: maxCanvas, contentSize: maxContent, filter: filter)
        }
        let content = min(maxContent, maxCanvas)
        let margin = max(0, (maxCanvas - content) / 2)
        let scale = min(Double(content) / Double(width), Double(content) / Double(height))
        let nw = max(1, Int((Double(width) * scale).rounded()))
        let nh = max(1, Int((Double(height) * scale).rounded()))
        let scaled = resized(to: nw, to: nh, filter: filter)

        var out = RGBAImage(width: nw + 2 * margin, height: nh + 2 * margin)
        for y in 0..<nh {
            for x in 0..<nw {
                let p = scaled.pixel(x, y)
                out.setPixel(margin + x, margin + y, p.r, p.g, p.b, p.a)
            }
        }
        return out
    }
}
