import Foundation

/// Everything the engines need to know about a movie file. Hashes are
/// computed once by the pipeline and shared by all engines.
public struct MovieFileDescriptor: Sendable, Hashable {
    public let url: URL
    public let fileSize: UInt64
    /// 64-bit hash used by OpenSubtitles and Napisy24.
    public let openSubtitlesHash: String?
    /// MD5 of the first 10 MiB, used by NapiProjekt.
    public let napiProjektChecksum: String?

    public var fileName: String { url.lastPathComponent }
    public var baseName: String { url.deletingPathExtension().lastPathComponent }

    public init(
        url: URL,
        fileSize: UInt64,
        openSubtitlesHash: String? = nil,
        napiProjektChecksum: String? = nil
    ) {
        self.url = url
        self.fileSize = fileSize
        self.openSubtitlesHash = openSubtitlesHash
        self.napiProjektChecksum = napiProjektChecksum
    }

    /// Computes both hashes from the file on disk.
    public static func hashing(url: URL) throws -> MovieFileDescriptor {
        let osHash = try MovieFileHasher.openSubtitlesHash(of: url)
        let npChecksum = try MovieFileHasher.napiProjektChecksum(of: url)
        return MovieFileDescriptor(
            url: url,
            fileSize: osHash.fileSize,
            openSubtitlesHash: osHash.value,
            napiProjektChecksum: npChecksum)
    }
}
