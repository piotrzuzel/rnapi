import Foundation
import RQNapiCore

/// NapiProjekt (napiprojekt.pl) — hash-addressed download, no real search.
/// Uses the `api3` endpoint, which returns the subtitle text directly as
/// base64 XML. (The older `dl.php` endpoint answers with BZip2-compressed
/// 7z archives, which the in-process PLzmaSDK extractor cannot decode.)
public struct NapiProjektEngine: SubtitleEngine {
    static let endpoint = URL(string: "http://napiprojekt.pl/api/api-napiprojekt3.php")!
    /// Client identity the api3 endpoint expects (the official client's).
    static let client = "NapiProjekt"
    static let clientVersion = "2.2.0.2399"

    public let metadata = EngineMetadata(
        id: "NapiProjekt",
        displayName: "NapiProjekt",
        websiteURL: URL(string: "http://www.napiprojekt.pl")!,
        registrationURL: URL(string: "http://www.napiprojekt.pl/rejestracja")!,
        supportsCredentials: true)

    private let session: URLSession
    private let credentials: EngineCredentials?
    private let temporaryDirectory: URL

    public init(
        session: URLSession = .shared,
        credentials: EngineCredentials? = nil,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.session = session
        self.credentials = credentials
        self.temporaryDirectory = temporaryDirectory
    }

    public func search(file: MovieFileDescriptor, language: SubtitleLanguage) async throws
        -> [FoundSubtitle]
    {
        guard let checksum = file.napiProjektChecksum else {
            throw EngineError.missingHash
        }

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "mode", value: "1"),
            URLQueryItem(name: "client", value: Self.client),
            URLQueryItem(name: "client_ver", value: Self.clientVersion),
            URLQueryItem(name: "downloaded_subtitles_id", value: checksum),
            URLQueryItem(name: "downloaded_subtitles_lang", value: Self.languageParameter(language)),
            URLQueryItem(name: "downloaded_subtitles_txt", value: "1"),
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

        let xml = String(decoding: data, as: UTF8.self)
        // A miss is a well-formed <result> without <status>success</status>.
        guard xml.contains("<status>success</status>"),
              let base64 = Self.cdata(of: "content", in: xml),
              let subtitleText = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              !subtitleText.isEmpty
        else {
            return []
        }

        let stashed = temporaryDirectory
            .appendingPathComponent("rqnapi-np-\(UUID().uuidString).txt")
        try subtitleText.write(to: stashed)

        var comment = ""
        if let author = Self.cdata(of: "author", in: xml) ?? Self.text(of: "author", in: xml),
           !author.isEmpty
        {
            comment = "author: \(author)"
        }

        return [
            FoundSubtitle(
                engineID: metadata.id,
                language: language,
                title: file.baseName,
                comment: comment,
                formatExtension: "txt",
                resolution: .unknown,
                handle: stashed.path)
        ]
    }

    public func download(_ subtitle: FoundSubtitle, to directory: URL) async throws -> URL {
        let stashed = URL(fileURLWithPath: subtitle.handle)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(stashed.lastPathComponent)
        try FileManager.default.copyItem(at: stashed, to: target)
        return target
    }

    /// Two-letter uppercase, except English which the service spells "ENG".
    static func languageParameter(_ language: SubtitleLanguage) -> String {
        let code = language.twoLetter.uppercased()
        return code == "EN" ? "ENG" : code
    }

    // MARK: - api3 XML helpers

    static func cdata(of element: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(element)><![CDATA["),
              let end = xml.range(of: "]]></\(element)>", range: start.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[start.upperBound..<end.lowerBound])
    }

    static func text(of element: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(element)>"),
              let end = xml.range(of: "</\(element)>", range: start.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[start.upperBound..<end.lowerBound])
    }
}
