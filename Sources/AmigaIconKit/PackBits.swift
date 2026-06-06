import Foundation

/// ByteRun1-style run-length compression as used by OS3.5+ ColorIcons
/// (GlowIcons), operating over a continuous **bit stream**.
///
/// The icon.library ColorIcon format stores image pixels at `depth` bits each
/// and palette components at 8 bits each, all interleaved with 8-bit RLE
/// control bytes in one non-byte-aligned stream. Decoding (per the icon.library
/// autodocs):
///
///   read an 8-bit control byte `c`:
///     * `c <  128` : copy the next `c + 1` items literally
///     * `c >  128` : repeat the next single item `257 - c` times
///     * `c == 128` : no-op
///
/// where each "item" is `itemBits` bits wide. Any valid mix of literal and
/// replicate runs decodes correctly, so the encoder here favours simplicity
/// and validity over achieving the theoretically smallest output.
public enum PackBits {

    /// Bit-packs `items` at `itemBits` each, MSB-first, with no compression.
    /// (ColorIcon `ImageFormat`/`PaletteFormat` == 0.)
    public static func packRaw(_ items: [Int], itemBits: Int) -> [UInt8] {
        var bw = BitWriter()
        for v in items { bw.writeBits(v, itemBits) }
        bw.align()
        return bw.bytes
    }

    /// RLE-compresses `items` into the bit stream described above.
    /// (ColorIcon `ImageFormat`/`PaletteFormat` == 1.)
    public static func packRLE(_ items: [Int], itemBits: Int) -> [UInt8] {
        var bw = BitWriter()
        var i = 0
        let n = items.count
        while i < n {
            // Look for a replicate run of length >= 2 (capped at 128).
            var run = 1
            while i + run < n && items[i + run] == items[i] && run < 128 { run += 1 }

            if run >= 2 {
                // Control byte 257 - run  ->  range 129...255.
                bw.writeBits(256 - (run - 1), 8)
                bw.writeBits(items[i], itemBits)
                i += run
            } else {
                // Literal run (capped at 128). Stop early if a replicate begins.
                var lit = [items[i]]
                i += 1
                while i < n && lit.count < 128 {
                    if i + 1 < n && items[i] == items[i + 1] { break }
                    lit.append(items[i])
                    i += 1
                }
                bw.writeBits(lit.count - 1, 8) // range 0...127
                for v in lit { bw.writeBits(v, itemBits) }
            }
        }
        bw.align()
        return bw.bytes
    }

    /// Inverse of `packRLE`, reading exactly `count` items. Used by tests to
    /// prove round-trip correctness, and available to callers for validation.
    public static func unpackRLE(_ bytes: [UInt8], itemBits: Int, count: Int) -> [Int] {
        var br = BitReader(bytes)
        var out: [Int] = []
        out.reserveCapacity(count)
        while out.count < count {
            let c = br.readBits(8)
            if c < 128 {
                for _ in 0...(c) { // c + 1 literals
                    out.append(br.readBits(itemBits))
                }
            } else if c > 128 {
                let value = br.readBits(itemBits)
                for _ in 0..<(257 - c) { out.append(value) }
            }
            // c == 128: no-op
        }
        return out
    }

    /// Inverse of `packRaw`.
    public static func unpackRaw(_ bytes: [UInt8], itemBits: Int, count: Int) -> [Int] {
        var br = BitReader(bytes)
        var out: [Int] = []
        out.reserveCapacity(count)
        for _ in 0..<count { out.append(br.readBits(itemBits)) }
        return out
    }
}
