import Compression
import Foundation

enum GzipError: Error {
    case notGzip
    case corrupted
}

/// Gzip (RFC 1952) decompression for XML-RPC subtitle payloads — PLzmaSDK
/// handles 7z/xz/tar but not gzip.
enum Gzip {
    static func inflate(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw GzipError.notGzip
        }

        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {  // FEXTRA
            guard bytes.count >= offset + 2 else { throw GzipError.corrupted }
            offset += 2 + (Int(bytes[offset]) | Int(bytes[offset + 1]) << 8)
        }
        for textFlag: UInt8 in [0x08, 0x10] where flags & textFlag != 0 {  // FNAME, FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }  // FHCRC

        // Trailer: CRC32 + uncompressed size (mod 2³²), 4 bytes each.
        guard bytes.count >= offset + 8 else { throw GzipError.corrupted }
        let deflated = data.subdata(in: (data.startIndex + offset)..<(data.endIndex - 8))
        let trailer = bytes.suffix(4)
        let expectedSize = trailer.enumerated().reduce(0) { size, byte in
            size | Int(byte.element) << (8 * byte.offset)
        }
        return try rawInflate(deflated, sizeHint: expectedSize)
    }

    /// Raw DEFLATE decode; Compression's `COMPRESSION_ZLIB` is headerless.
    private static func rawInflate(_ data: Data, sizeHint: Int) throws -> Data {
        let bufferSize = min(max(sizeHint, 64 * 1024), 64 * 1024 * 1024)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        var stream = compression_stream(
            dst_ptr: destination, dst_size: bufferSize, src_ptr: destination, src_size: 0,
            state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            == COMPRESSION_STATUS_OK
        else { throw GzipError.corrupted }
        defer { compression_stream_destroy(&stream) }

        var output = Data()
        try data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            stream.src_ptr = source.bindMemory(to: UInt8.self).baseAddress!
            stream.src_size = source.count
            while true {
                stream.dst_ptr = destination
                stream.dst_size = bufferSize
                let status = compression_stream_process(
                    &stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END else {
                    throw GzipError.corrupted
                }
                output.append(destination, count: bufferSize - stream.dst_size)
                if status == COMPRESSION_STATUS_END { return }
            }
        }
        return output
    }
}
