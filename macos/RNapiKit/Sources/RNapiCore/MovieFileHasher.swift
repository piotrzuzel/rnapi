import CryptoKit
import Foundation

public enum MovieHashError: Error, Sendable {
    case unreadable(URL)
}

/// Result of the OpenSubtitles/Napisy24 64-bit movie hash.
public struct OpenSubtitlesHash: Sendable, Hashable {
    /// 16-character lowercase hexadecimal hash.
    public let value: String
    public let fileSize: UInt64
}

/// File-hash algorithms used by the subtitle services.
public enum MovieFileHasher {
    /// 64-bit hash used by OpenSubtitles and Napisy24:
    /// `fileSize + Σ(first 64 KiB as LE UInt64) + Σ(last 64 KiB as LE UInt64)`
    /// with wrapping addition.
    public static func openSubtitlesHash(of url: URL) throws -> OpenSubtitlesHash {
        guard let file = try? FileHandle(forReadingFrom: url) else {
            throw MovieHashError.unreadable(url)
        }
        defer { try? file.close() }

        let chunkSize = 65536
        let fileSize = try fileLength(of: file)
        var hash = fileSize

        hash &+= sumChunk(try file.read(upToCount: chunkSize) ?? Data())
        try file.seek(toOffset: fileSize > UInt64(chunkSize) ? fileSize - UInt64(chunkSize) : 0)
        hash &+= sumChunk(try file.read(upToCount: chunkSize) ?? Data())

        return OpenSubtitlesHash(value: String(format: "%016llx", hash), fileSize: fileSize)
    }

    /// MD5 of the first 10 MiB of the file, lowercase hex — NapiProjekt's
    /// movie checksum.
    public static func napiProjektChecksum(of url: URL) throws -> String {
        guard let file = try? FileHandle(forReadingFrom: url) else {
            throw MovieHashError.unreadable(url)
        }
        defer { try? file.close() }

        var md5 = Insecure.MD5()
        var remaining = 10 * 1024 * 1024
        let blockSize = 1024 * 1024
        while remaining > 0 {
            guard let block = try file.read(upToCount: min(blockSize, remaining)),
                  !block.isEmpty
            else { break }
            md5.update(data: block)
            remaining -= block.count
        }
        return md5.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// NapiProjekt's `t=` request digest: a 5-character transform of the
    /// 32-character MD5 checksum. Verbatim port of legacy `npFDigest`.
    public static func npFDigest(of checksum: String) -> String {
        guard checksum.count == 32 else { return "" }
        let chars = Array(checksum.unicodeScalars)

        let idx = [0xE, 0x3, 0x6, 0x8, 0x2]
        let mul = [2, 2, 5, 4, 3]
        let add = [0x0, 0xD, 0x10, 0xB, 0x5]

        var out = ""
        for j in 0...4 {
            let t = add[j] + hexValue(chars[idx[j]])
            // Legacy uses QString::mid(t, 2), which clamps at the string end.
            let pair = String(String.UnicodeScalarView(chars[t..<min(t + 2, 32)]))
            let v = Int(pair, radix: 16) ?? 0
            out += String((v * mul[j]) % 0x10, radix: 16)
        }
        return out
    }

    private static func hexValue(_ scalar: Unicode.Scalar) -> Int {
        Int(String(scalar), radix: 16) ?? 0
    }

    private static func fileLength(of file: FileHandle) throws -> UInt64 {
        let size = try file.seekToEnd()
        try file.seek(toOffset: 0)
        return size
    }

    /// Sums complete little-endian 8-byte words; a trailing partial word is
    /// ignored (matches legacy behavior for files not multiple of 8 bytes).
    private static func sumChunk(_ data: Data) -> UInt64 {
        var sum: UInt64 = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let words = raw.count / 8
            for i in 0..<words {
                sum &+= UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self))
            }
        }
        return sum
    }
}
