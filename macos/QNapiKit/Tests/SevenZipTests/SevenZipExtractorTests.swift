import Foundation
import PLzmaSDK
import Testing

@testable import SevenZip

/// Builds an AES-encrypted 7z archive in memory via PLzmaSDK's encoder —
/// the same archive shape NapiProjekt serves (password-protected 7z with a
/// single text file inside).
private func makeEncryptedArchive(content: String, fileName: String, password: String) throws
    -> Data
{
    let outStream = try OutStream()
    let encoder = try Encoder(stream: outStream, fileType: .sevenZ, method: .LZMA2)
    try encoder.setPassword(password)
    try encoder.setShouldEncryptContent(true)
    let inStream = try InStream(dataCopy: Data(content.utf8))
    try encoder.add(stream: inStream, archivePath: Path(fileName))
    guard try encoder.open(), try encoder.compress() else {
        throw ArchiveError.extractionFailed(URL(fileURLWithPath: "/dev/null"))
    }
    return try outStream.copyContent()
}

@Suite struct SevenZipExtractorTests {
    private let napiPassword = "iBlm8NTigvru0Jr0"

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("qnapi-7z-\(UUID().uuidString)")
    }

    @Test func extractsPasswordProtectedArchiveFromMemory() throws {
        let subtitle = "1\n00:00:01,000 --> 00:00:02,000\nHello\n"
        let archive = try makeEncryptedArchive(
            content: subtitle, fileName: "napisy.srt", password: napiPassword)

        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let files = try SevenZipExtractor().extractAll(
            from: archive, password: napiPassword, to: dir)

        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent == "napisy.srt")
        let extracted = try String(contentsOf: try #require(files.first), encoding: .utf8)
        #expect(extracted == subtitle)
    }

    @Test func extractsArchiveFromFile() throws {
        let archive = try makeEncryptedArchive(
            content: "test", fileName: "file.txt", password: napiPassword)
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qnapi-test-\(UUID().uuidString).7z")
        try archive.write(to: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let files = try SevenZipExtractor().extractAll(
            from: archiveURL, password: napiPassword, to: dir)
        #expect(files.map(\.lastPathComponent) == ["file.txt"])
    }

    @Test func wrongPasswordFails() throws {
        let archive = try makeEncryptedArchive(
            content: "secret", fileName: "file.txt", password: napiPassword)
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: ArchiveError.self) {
            try SevenZipExtractor().extractAll(from: archive, password: "wrong", to: dir)
        }
    }
}
