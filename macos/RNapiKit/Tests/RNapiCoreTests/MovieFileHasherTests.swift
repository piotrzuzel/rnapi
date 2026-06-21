import Foundation
import Testing

@testable import RNapiCore

/// Deterministic pseudo-file: byte i = (i*7+13) & 0xff. Golden values were
/// computed with an independent Python implementation of each algorithm.
private func synthesizedFile(bytes count: Int) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("rnapi-hash-fixture-\(count).bin")
    var data = Data(capacity: count)
    for i in 0..<count {
        data.append(UInt8((i * 7 + 13) & 0xff))
    }
    try data.write(to: url)
    return url
}

@Suite struct MovieFileHasherTests {
    @Test func openSubtitlesHashOfLargeFile() throws {
        let url = try synthesizedFile(bytes: 200_000)
        let hash = try MovieFileHasher.openSubtitlesHash(of: url)
        #expect(hash.value == "df1f5f9fe0234d40")
        #expect(hash.fileSize == 200_000)
    }

    @Test func openSubtitlesHashOfFileWithOverlappingWindows() throws {
        let url = try synthesizedFile(bytes: 70_000)
        let hash = try MovieFileHasher.openSubtitlesHash(of: url)
        #expect(hash.value == "df1f5f9fe0215170")
    }

    @Test func napiProjektChecksum() throws {
        let url = try synthesizedFile(bytes: 200_000)
        let checksum = try MovieFileHasher.napiProjektChecksum(of: url)
        #expect(checksum == "1864c7bdedbe7c28714025ff5a0d871a")
    }

    @Test func npFDigestVectors() {
        #expect(MovieFileHasher.npFDigest(of: "1864c7bdedbe7c28714025ff5a0d871a") == "88805")
        #expect(MovieFileHasher.npFDigest(of: "fc3960c966e034a1d3fc6783ccb79c3d") == "06cc2")
        #expect(MovieFileHasher.npFDigest(of: "9e107d9d372bb6826bd81d3542a419d6") == "e0287")
        #expect(MovieFileHasher.npFDigest(of: "tooshort") == "")
    }

    @Test func missingFileThrows() {
        #expect(throws: MovieHashError.self) {
            try MovieFileHasher.openSubtitlesHash(of: URL(fileURLWithPath: "/nonexistent/file.mkv"))
        }
    }
}
