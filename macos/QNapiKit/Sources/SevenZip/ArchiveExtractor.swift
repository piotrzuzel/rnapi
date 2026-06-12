import Foundation

public enum ArchiveError: Error, Sendable {
    case cannotOpen(URL)
    case extractionFailed(URL)
}

/// Extracts subtitle archives returned by the download engines.
public protocol ArchiveExtractor: Sendable {
    /// Extracts every file in `archive` into `directory` and returns the
    /// extracted file URLs.
    func extractAll(from archive: URL, password: String?, to directory: URL) throws -> [URL]

    /// Extracts an in-memory archive (engines receive archives as HTTP
    /// response bodies) into `directory`.
    func extractAll(from data: Data, password: String?, to directory: URL) throws -> [URL]
}
