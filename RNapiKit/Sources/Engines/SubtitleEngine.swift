import Foundation
import RNapiCore

public struct EngineMetadata: Sendable, Hashable {
    /// Stable identifier used in settings (engine order, credentials).
    public let id: String
    public let displayName: String
    public let websiteURL: URL
    public let registrationURL: URL?
    /// Whether user credentials make sense for this engine.
    public let supportsCredentials: Bool

    public init(
        id: String, displayName: String, websiteURL: URL,
        registrationURL: URL? = nil, supportsCredentials: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.websiteURL = websiteURL
        self.registrationURL = registrationURL
        self.supportsCredentials = supportsCredentials
    }
}

public enum EngineError: Error, Sendable {
    case missingHash
    case httpError(statusCode: Int)
    case invalidResponse
    case authenticationFailed
    case downloadQuotaExceeded
    case noSubtitleInArchive
}

/// A subtitle download service client.
public protocol SubtitleEngine: Sendable {
    var metadata: EngineMetadata { get }

    /// Searches for subtitles matching the movie in the given language.
    /// Returns an empty array when the service has nothing (not an error).
    func search(file: MovieFileDescriptor, language: SubtitleLanguage) async throws
        -> [FoundSubtitle]

    /// Fetches/unpacks one search result into `directory` and returns the
    /// subtitle file URL, ready for post-processing.
    func download(_ subtitle: FoundSubtitle, to directory: URL) async throws -> URL
}

/// Extensions recognized as subtitle files when picking from an archive.
let subtitleFileExtensions: Set<String> = ["srt", "sub", "txt"]

/// 7z archive magic bytes. The Polish services answer HTTP 200 with an HTML
/// error page on hiccups; anything that is not a 7z archive must be treated
/// as "no subtitles" (legacy validated this by extracting during search).
let sevenZipMagic = Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])

func firstSubtitleFile(in files: [URL]) throws -> URL {
    guard
        let subtitle = files.first(where: {
            subtitleFileExtensions.contains($0.pathExtension.lowercased())
        }) ?? files.first
    else {
        throw EngineError.noSubtitleInArchive
    }
    return subtitle
}
