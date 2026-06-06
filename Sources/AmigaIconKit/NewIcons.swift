import Foundation

/// NewIcons encoder (the OS3.x format that smuggles a palette-indexed colour
/// image into the icon's **tool types**, decoded by `newicon.library` /
/// PowerIcons / the NewIcons patch).
///
/// ⚠️ EXPERIMENTAL — VERIFY ON REAL WORKBENCH ⚠️
/// NewIcons was never officially documented; this encoder is a best-effort
/// reconstruction of the on-disk layout. The transfer encoding (7-bit printable
/// mapping) and overall structure follow the commonly-cited description, but
/// the exact header packing and run-length scheme should be checked against a
/// known-good reference icon and adjusted if Workbench does not render it. It is
/// deliberately isolated from the Classic and ColorIcon paths (which are not
/// experimental) so it can be corrected without touching them.
///
/// The result is a list of tool-type strings (`IM1=…`, `IM2=…`) to be merged
/// into the icon's tool types ahead of any user entries.
public enum NewIcons {

    /// Maximum payload characters per `IMn=` tool-type line before continuing on
    /// the next line. Kept conservative to stay within tool-type length limits.
    static let maxLineLength = 124

    public static func encode(normal: IndexedImage, selected: IndexedImage?) -> [String] {
        var lines: [String] = []
        lines += encodeImage(normal, key: "IM1")
        if let sel = selected {
            lines += encodeImage(sel, key: "IM2")
        }
        return lines
    }

    private static func encodeImage(_ img: IndexedImage, key: String) -> [String] {
        let numColors = img.palette.count
        let hasTransparency = img.transparentIndex != nil

        // --- Header characters (written directly, not transfer-encoded). ---
        var payload: [UInt8] = []
        payload.append(hasTransparency ? UInt8(ascii: "B") : UInt8(ascii: "C"))
        payload.append(UInt8(0x21 + min(0xFF - 0x21, img.width)))
        payload.append(UInt8(0x21 + min(0xFF - 0x21, img.height)))
        payload.append(UInt8(0x21 + ((numColors >> 6) & 0x3F)))
        payload.append(UInt8(0x21 + (numColors & 0x3F)))

        // --- Body bit stream: palette RGB bytes, then RLE-packed indices. ---
        var bits = BitWriter()
        for c in img.palette {
            bits.writeBits(Int(c.r), 8)
            bits.writeBits(Int(c.g), 8)
            bits.writeBits(Int(c.b), 8)
        }
        // Indices, RLE-compressed at the palette's bit depth, appended to the
        // same stream. (Reuses the ByteRun1-on-bitstream packer for consistency;
        // the genuine NewIcons RLE may differ — see warning above.)
        let depth = img.depth
        let packed = PackBits.packRLE(img.indices, itemBits: depth)
        for byte in packed { bits.writeBits(Int(byte), 8) }
        bits.align()

        // --- Transfer-encode the body bit stream, 7 bits -> 1 printable byte. ---
        payload += transferEncode(bits.bytes)

        // --- Split into IMn= lines. ---
        // Latin-1: tool types are 8-bit, and the transfer encoding emits bytes up
        // to 0xD0. Building the string from raw scalars keeps every byte intact
        // (UTF-8 would mangle anything > 0x7F).
        let text = String(String.UnicodeScalarView(payload.map { Unicode.Scalar($0) }))
        return chunk(text, size: maxLineLength).map { "\(key)=\($0)" }
    }

    // MARK: - Decoding (round-trip / validation)

    /// Decodes NewIcons images out of an icon's tool types. Pairs with `encode`;
    /// gathers the `IM1=`/`IM2=` continuation lines and reverses the transfer
    /// encoding, palette and RLE.
    ///
    /// ⚠️ Like the encoder this is unverified against a real Workbench, and the
    /// transparent-pen index in particular is a best guess (index 0). Use it for
    /// round-trip validation of the codec, not as a source of truth.
    public static func decode(_ toolTypes: [String]) -> (normal: IndexedImage?, selected: IndexedImage?) {
        func payload(_ key: String) -> [UInt8]? {
            let prefix = key + "="
            let parts = toolTypes.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
            guard !parts.isEmpty else { return nil }
            return parts.joined().unicodeScalars.map { UInt8($0.value & 0xFF) }
        }
        return (payload("IM1").flatMap(decodeImage), payload("IM2").flatMap(decodeImage))
    }

    static func decodeImage(_ payload: [UInt8]) -> IndexedImage? {
        guard payload.count >= 5 else { return nil }
        let hasTransparency = payload[0] == UInt8(ascii: "B")
        let width = Int(payload[1]) - 0x21
        let height = Int(payload[2]) - 0x21
        let numColors = ((Int(payload[3]) - 0x21) << 6) | (Int(payload[4]) - 0x21)
        guard width > 0, height > 0, numColors > 0 else { return nil }

        let body = transferDecode(Array(payload[5...]))
        guard body.count >= numColors * 3 else { return nil }
        var palette: [RGB] = []
        palette.reserveCapacity(numColors)
        for i in 0..<numColors { palette.append(RGB(body[i * 3], body[i * 3 + 1], body[i * 3 + 2])) }

        let depth = max(1, Int(ceil(log2(Double(max(2, numColors))))))
        let indices = PackBits.unpackRLE(Array(body[(numColors * 3)...]), itemBits: depth, count: width * height)
        return IndexedImage(width: width, height: height, indices: indices,
                            palette: palette, transparentIndex: hasTransparency ? 0 : nil)
    }

    /// Inverse of `transferEncode`: maps each printable byte back to its 7-bit
    /// value and re-assembles the original byte stream (trailing pad bits, which
    /// the RLE decoder ignores, may remain).
    static func transferDecode(_ bytes: [UInt8]) -> [UInt8] {
        var bw = BitWriter()
        for b in bytes { if let v = dec7(b) { bw.writeBits(v, 7) } }
        bw.align()
        return bw.bytes
    }

    // MARK: - 7-bit printable transfer encoding

    /// Maps a 7-bit value (0...127) to a printable byte:
    ///   0x00...0x4F -> 0x20...0x6F   (+0x20)
    ///   0x50...0x7F -> 0xA1...0xD0   (+0x51)
    @inline(__always) static func enc7(_ v: Int) -> UInt8 {
        v <= 0x4F ? UInt8(v + 0x20) : UInt8(v + 0x51)
    }

    /// Inverse of `enc7`. Returns `nil` for bytes outside the encoded ranges.
    @inline(__always) static func dec7(_ c: UInt8) -> Int? {
        if c >= 0x20 && c <= 0x6F { return Int(c) - 0x20 }
        if c >= 0xA1 && c <= 0xD0 { return Int(c) - 0x51 }
        return nil
    }

    /// Re-packs a byte stream into 7-bit groups and maps each to a printable byte.
    static func transferEncode(_ bytes: [UInt8]) -> [UInt8] {
        var reader = BitReader(bytes)
        let totalBits = bytes.count * 8
        var out: [UInt8] = []
        var consumed = 0
        while consumed < totalBits {
            let take = min(7, totalBits - consumed)
            var v = reader.readBits(take)
            if take < 7 { v <<= (7 - take) } // left-align trailing partial group
            out.append(enc7(v))
            consumed += take
        }
        return out
    }

    private static func chunk(_ s: String, size: Int) -> [String] {
        guard size > 0, !s.isEmpty else { return s.isEmpty ? [] : [s] }
        var result: [String] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            let end = s.index(idx, offsetBy: size, limitedBy: s.endIndex) ?? s.endIndex
            result.append(String(s[idx..<end]))
            idx = end
        }
        return result
    }
}
