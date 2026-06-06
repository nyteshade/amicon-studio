import Foundation

/// Accumulates bytes in **big-endian** order, the byte order used throughout
/// the Amiga `.info` / IFF file formats (the Amiga is a 68k, big-endian machine).
public struct BinaryWriter {
    public private(set) var data: [UInt8] = []

    public init() {}

    public mutating func u8(_ v: UInt8) { data.append(v) }

    public mutating func u16(_ v: UInt16) {
        data.append(UInt8((v >> 8) & 0xFF))
        data.append(UInt8(v & 0xFF))
    }

    public mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }

    public mutating func u32(_ v: UInt32) {
        data.append(UInt8((v >> 24) & 0xFF))
        data.append(UInt8((v >> 16) & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
        data.append(UInt8(v & 0xFF))
    }

    public mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }

    public mutating func bytes(_ b: [UInt8]) { data.append(contentsOf: b) }

    /// Appends raw ASCII bytes (used for IFF chunk identifiers like `FORM`).
    public mutating func ascii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }

    /// Pads to an even byte count with a zero byte (IFF chunks must be word aligned).
    public mutating func padEven() {
        if data.count % 2 != 0 { data.append(0) }
    }
}

/// Writes individual bits, most-significant-bit first. Used by the GlowIcon
/// (ColorIcon) packer, where 8-bit RLE control bytes and N-bit pixels share a
/// single continuous, non-byte-aligned bit stream.
public struct BitWriter {
    public private(set) var bytes: [UInt8] = []
    private var current: UInt8 = 0
    private var bitCount: Int = 0

    public init() {}

    public mutating func writeBits(_ value: Int, _ count: Int) {
        var i = count - 1
        while i >= 0 {
            let bit = (value >> i) & 1
            current = (current << 1) | UInt8(bit)
            bitCount += 1
            if bitCount == 8 {
                bytes.append(current)
                current = 0
                bitCount = 0
            }
            i -= 1
        }
    }

    /// Flushes any partial byte, padding the low bits with zeroes.
    public mutating func align() {
        if bitCount > 0 {
            current = current << (8 - bitCount)
            bytes.append(current)
            current = 0
            bitCount = 0
        }
    }
}

/// Reads bits MSB-first. Companion to `BitWriter`; used by the round-trip tests
/// and by callers that want to validate produced data.
public struct BitReader {
    private let bytes: [UInt8]
    private var bytePos = 0
    private var bitPos = 0 // 0 == MSB of current byte

    public init(_ bytes: [UInt8]) { self.bytes = bytes }

    public mutating func readBits(_ count: Int) -> Int {
        var result = 0
        for _ in 0..<count {
            let byte = bytePos < bytes.count ? bytes[bytePos] : 0
            let bit = (Int(byte) >> (7 - bitPos)) & 1
            result = (result << 1) | bit
            bitPos += 1
            if bitPos == 8 { bitPos = 0; bytePos += 1 }
        }
        return result
    }
}
