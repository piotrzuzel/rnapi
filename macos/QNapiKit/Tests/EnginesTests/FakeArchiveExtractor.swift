import Foundation
import SevenZip

/// Pretends every archive contains the given files; records the password.
struct FakeArchiveExtractor: ArchiveExtractor {
    let fileNames: [String]
    let expectedPassword: String?

    func extractAll(from archive: URL, password: String?, to directory: URL) throws -> [URL] {
        guard password == expectedPassword else {
            throw ArchiveError.extractionFailed(archive)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try fileNames.map { name in
            let url = directory.appendingPathComponent(name)
            try Data("subtitle".utf8).write(to: url)
            return url
        }
    }

    func extractAll(from data: Data, password: String?, to directory: URL) throws -> [URL] {
        try extractAll(from: URL(fileURLWithPath: "/dev/null"), password: password, to: directory)
    }
}
