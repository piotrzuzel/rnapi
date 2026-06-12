import Foundation
import QNapiCore
import SevenZip

/// Napisy24 (napisy24.pl) — Polish subtitles only. Agent-style POST API;
/// a successful response is `OK-2||<7z archive bytes>`.
public struct Napisy24Engine: SubtitleEngine {
    static let endpoint = URL(string: "http://napisy24.pl/run/CheckSubAgent.php")!
    /// Shared agent credentials used when the user has not configured any
    /// (same fallback as the legacy client).
    static let defaultCredentials = EngineCredentials(
        username: "tantalosus", password: "susolatnat")

    public let metadata = EngineMetadata(
        id: "Napisy24",
        displayName: "Napisy24",
        websiteURL: URL(string: "http://napisy24.pl")!,
        registrationURL: URL(string: "http://napisy24.pl/rejestracja/")!,
        supportsCredentials: true)

    private let session: URLSession
    private let extractor: any ArchiveExtractor
    private let credentials: EngineCredentials?
    private let temporaryDirectory: URL

    public init(
        session: URLSession = .shared,
        extractor: any ArchiveExtractor = SevenZipExtractor(),
        credentials: EngineCredentials? = nil,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.session = session
        self.extractor = extractor
        self.credentials = credentials
        self.temporaryDirectory = temporaryDirectory
    }

    public func search(file: MovieFileDescriptor, language: SubtitleLanguage) async throws
        -> [FoundSubtitle]
    {
        guard language.twoLetter == "pl" else { return [] }
        guard let hash = file.openSubtitlesHash else {
            throw EngineError.missingHash
        }

        let effective = credentials ?? Self.defaultCredentials
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "postAction", value: "CheckSub"),
            URLQueryItem(name: "ua", value: effective.username),
            URLQueryItem(name: "ap", value: effective.password),
            URLQueryItem(name: "fh", value: hash),
            URLQueryItem(name: "fs", value: String(file.fileSize)),
            URLQueryItem(name: "fn", value: file.fileName),
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw EngineError.httpError(statusCode: http.statusCode)
        }

        guard data.prefix(4) == Data("OK-2".utf8),
              let separator = data.range(of: Data("||".utf8))
        else {
            return []
        }

        let archiveFile = temporaryDirectory
            .appendingPathComponent("qnapi-n24-\(UUID().uuidString).7z")
        try data[separator.upperBound...].write(to: archiveFile)

        return [
            FoundSubtitle(
                engineID: metadata.id,
                language: language,
                title: file.baseName,
                formatExtension: "txt",
                resolution: .unknown,
                handle: archiveFile.path)
        ]
    }

    public func download(_ subtitle: FoundSubtitle, to directory: URL) async throws -> URL {
        let archive = URL(fileURLWithPath: subtitle.handle)
        let files = try extractor.extractAll(from: archive, password: nil, to: directory)
        return try firstSubtitleFile(in: files)
    }
}
