import Foundation
import RNapiCore
import SevenZip

/// NapiProjekt (napiprojekt.pl) — hash-addressed download, no real search.
/// The `dl.php` GET either returns a password-protected 7z archive with the
/// subtitles or a body starting with "NPc" meaning "no subtitles".
public struct NapiProjektEngine: SubtitleEngine {
    static let archivePassword = "iBlm8NTigvru0Jr0"
    static let downloadURL = "http://www.napiprojekt.pl/unit_napisy/dl.php"

    public let metadata = EngineMetadata(
        id: "NapiProjekt",
        displayName: "NapiProjekt",
        websiteURL: URL(string: "http://www.napiprojekt.pl")!,
        registrationURL: URL(string: "http://www.napiprojekt.pl/rejestracja")!,
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
        guard let checksum = file.napiProjektChecksum else {
            throw EngineError.missingHash
        }

        var components = URLComponents(string: Self.downloadURL)!
        components.queryItems = [
            URLQueryItem(name: "l", value: Self.languageParameter(language)),
            URLQueryItem(name: "f", value: checksum),
            URLQueryItem(name: "t", value: MovieFileHasher.npFDigest(of: checksum)),
            URLQueryItem(name: "v", value: "other"),
            URLQueryItem(name: "kolejka", value: "false"),
            URLQueryItem(name: "nick", value: credentials?.username ?? ""),
            URLQueryItem(name: "pass", value: credentials?.password ?? ""),
            URLQueryItem(name: "napios", value: "Mac OS X"),
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw EngineError.httpError(statusCode: http.statusCode)
        }

        // "NPc" prefix is the service's "no subtitles" marker.
        if data.prefix(3) == Data("NPc".utf8) {
            return []
        }

        let archiveFile = temporaryDirectory
            .appendingPathComponent("rnapi-np-\(UUID().uuidString).7z")
        try data.write(to: archiveFile)

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
        let files = try extractor.extractAll(
            from: archive, password: Self.archivePassword, to: directory)
        return try firstSubtitleFile(in: files)
    }

    /// Two-letter uppercase, except English which the service spells "ENG".
    static func languageParameter(_ language: SubtitleLanguage) -> String {
        let code = language.twoLetter.uppercased()
        return code == "EN" ? "ENG" : code
    }
}
