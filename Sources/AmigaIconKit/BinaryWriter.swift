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

/// Reads **big-endian** scalars from a byte buffer, the companion to
/// `BinaryWriter`. Used by the `.info` decoder (and its round-trip tests).
/// Every read advances `offset` and throws `BinaryReader.Error.outOfBounds`
/// rather than trapping if the buffer is too short, so a truncated or malformed
/// icon fails cleanly instead of crashing.
public struct BinaryReader {
    public let data: [UInt8]
    public private(set) var offset: Int

    public enum Error: Swift.Error, Equatable { case outOfBounds }

    public init(_ data: [UInt8], offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public var remaining: Int { data.count - offset }
    public var isAtEnd: Bool { offset >= data.count }

    public mutating func u8() throws -> UInt8 {
        guard offset < data.count else { throw Error.outOfBounds }
        defer { offset += 1 }
        return data[offset]
    }

    public mutating func u16() throws -> UInt16 {
        let hi = try u8(), lo = try u8()
        return (UInt16(hi) << 8) | UInt16(lo)
    }

    public mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    public mutating func u32() throws -> UInt32 {
        let a = try u8(), b = try u8(), c = try u8(), d = try u8()
        return (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(c) << 8) | UInt32(d)
    }

    public mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }

    /// Reads `n` raw bytes.
    public mutating func bytes(_ n: Int) throws -> [UInt8] {
        guard n >= 0, offset + n <= data.count else { throw Error.outOfBounds }
        defer { offset += n }
        return Array(data[offset ..< offset + n])
    }

    /// Reads `n` bytes as ASCII (used for IFF chunk identifiers like `FORM`).
    public mutating func ascii(_ n: Int) throws -> String {
        String(decoding: try bytes(n), as: UTF8.self)
    }

    /// Returns the next `n` bytes as ASCII without advancing, or `nil` if fewer
    /// than `n` bytes remain. Used to test for an optional trailing `FORM ICON`.
    public func peekAscii(_ n: Int) -> String? {
        guard offset + n <= data.count else { return nil }
        return String(decoding: data[offset ..< offset + n], as: UTF8.self)
    }

    public mutating func skip(_ n: Int) throws {
        guard n >= 0, offset + n <= data.count else { throw Error.outOfBounds }
        offset += n
    }

    /// Repositions the cursor to an absolute offset within the buffer.
    public mutating func seek(to newOffset: Int) throws {
        guard newOffset >= 0, newOffset <= data.count else { throw Error.outOfBounds }
        offset = newOffset
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
