import Foundation
import PLzmaSDK

/// 7z extraction backed by PLzmaSDK (in-process, supports AES-encrypted
/// archives such as NapiProjekt's password-protected responses).
public struct SevenZipExtractor: ArchiveExtractor {
    public init() {}

    public func extractAll(from archive: URL, password: String?, to directory: URL) throws -> [URL] {
        let stream: InStream
        do {
            stream = try InStream(path: Path(archive.path))
        } catch {
            throw ArchiveError.cannotOpen(archive)
        }
        return try extractAll(stream: stream, password: password, to: directory, source: archive)
    }

    public func extractAll(from data: Data, password: String?, to directory: URL) throws -> [URL] {
        let stream: InStream
        do {
            stream = try InStream(dataCopy: data)
        } catch {
            throw ArchiveError.cannotOpen(directory)
        }
        return try extractAll(stream: stream, password: password, to: directory, source: directory)
    }

    private func extractAll(
        stream: InStream, password: String?, to directory: URL, source: URL
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let decoder = try Decoder(stream: stream, fileType: .sevenZ)
            if let password {
                try decoder.setPassword(password)
            }
            guard try decoder.open() else {
                throw ArchiveError.cannotOpen(source)
            }

            let items = try decoder.items()
            guard try decoder.extract(to: Path(directory.path), itemsFullPath: false) else {
                throw ArchiveError.extractionFailed(source)
            }

            var extracted: [URL] = []
            for index in 0..<items.count {
                let item = try items.item(at: index)
                let name = try item.path().lastComponent().description
                extracted.append(directory.appendingPathComponent(name))
            }
            return extracted
        } catch let error as ArchiveError {
            throw error
        } catch {
            throw ArchiveError.extractionFailed(source)
        }
    }
}
