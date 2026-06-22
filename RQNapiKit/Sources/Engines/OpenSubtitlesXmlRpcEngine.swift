import Foundation
import RQNapiCore

/// OpenSubtitles via the legacy XML-RPC API (api.opensubtitles.org) — the
/// API the original QNapi uses. Unlike the REST API it accepts anonymous
/// logins and needs no API key, so it is the fallback when none is
/// configured. An actor because it lazily logs in and caches the session
/// token across calls.
public actor OpenSubtitlesXmlRpcEngine: SubtitleEngine {
    static let endpoint = URL(string: "https://api.opensubtitles.org/xml-rpc")!
    /// The XML-RPC API rejects unregistered user agents; this is QNapi's
    /// registered one and must be sent verbatim.
    static let userAgent = "QNapi v0.2.4-snapshot"

    public nonisolated let metadata = EngineMetadata(
        id: "OpenSubtitles",
        displayName: "OpenSubtitles",
        websiteURL: URL(string: "https://www.opensubtitles.org")!,
        registrationURL: URL(string: "https://www.opensubtitles.org/newuser")!,
        supportsCredentials: true)

    private let session: URLSession
    private let credentials: EngineCredentials?
    private var token: String?

    public init(credentials: EngineCredentials? = nil, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: - SubtitleEngine

    public func search(file: MovieFileDescriptor, language: SubtitleLanguage) async throws
        -> [FoundSubtitle]
    {
        guard let movieHash = file.openSubtitlesHash else {
            throw EngineError.missingHash
        }

        let token = try await ensureToken(language: language)
        let response = try await call(
            "SearchSubtitles",
            [
                .string(token),
                .array([
                    .structure([
                        "sublanguageid": .string(language.threeLetter),
                        "moviehash": .string(movieHash),
                        "moviebytesize": .string(String(file.fileSize)),
                    ])
                ]),
            ])

        // "data" is boolean false when nothing matched.
        guard let items = response["data"]?.arrayValue else { return [] }

        return items.compactMap { item -> FoundSubtitle? in
            guard let fields = item.structValue,
                  let subtitleID = fields["IDSubtitleFile"]?.stringValue, !subtitleID.isEmpty
            else { return nil }

            let subtitleFileName = fields["SubFileName"]?.stringValue ?? ""
            let releaseName = (fields["MovieReleaseName"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Legacy ranking: bad flag wins; otherwise a subtitle or release
            // name matching the movie's base name is a confirmed match.
            var resolution = SubtitleResolution.unknown
            if (fields["SubBad"]?.stringValue ?? "0") != "0" {
                resolution = .bad
            } else if (subtitleFileName as NSString).deletingPathExtension == file.baseName {
                resolution = .good
            } else if !releaseName.isEmpty,
                      file.baseName.range(of: releaseName, options: [.caseInsensitive, .anchored])
                          != nil
            {
                resolution = .good
            }

            let formatExtension = (subtitleFileName as NSString).pathExtension
            return FoundSubtitle(
                engineID: metadata.id,
                language: language,
                title: releaseName.isEmpty ? file.baseName : releaseName,
                comment: fields["SubAuthorComment"]?.stringValue ?? "",
                formatExtension: formatExtension.isEmpty ? "srt" : formatExtension.lowercased(),
                resolution: resolution,
                handle: subtitleID)
        }
        .sorted { $0.resolution > $1.resolution }
    }

    public func download(_ subtitle: FoundSubtitle, to directory: URL) async throws -> URL {
        let token = try await ensureToken(language: subtitle.language)
        let response = try await call(
            "DownloadSubtitles", [.string(token), .array([.string(subtitle.handle)])])

        guard let item = response["data"]?.arrayValue?.first,
              let base64 = item["data"]?.stringValue,
              let compressed = Data(
                base64Encoded: base64, options: .ignoreUnknownCharacters)
        else { throw EngineError.invalidResponse }

        let content: Data
        do {
            content = try Gzip.inflate(compressed)
        } catch {
            throw EngineError.invalidResponse
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory
            .appendingPathComponent("rqnapi-os-\(subtitle.handle).\(subtitle.formatExtension)")
        try content.write(to: target)
        return target
    }

    // MARK: - Internals

    private func ensureToken(language: SubtitleLanguage) async throws -> String {
        if let token { return token }

        let response = try await call(
            "LogIn",
            [
                .string(credentials?.username ?? ""),
                .string(credentials?.password ?? ""),
                .string(language.twoLetter),
                .string(Self.userAgent),
            ])
        guard let token = response["token"]?.stringValue, !token.isEmpty else {
            throw EngineError.authenticationFailed
        }
        self.token = token
        return token
    }

    private func call(_ method: String, _ parameters: [XmlRpcValue]) async throws -> XmlRpcValue {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = XmlRpcRequest.body(method: method, parameters: parameters)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw EngineError.httpError(statusCode: http.statusCode)
        }

        let value = try XmlRpcResponseParser.parse(data)
        // The API reports errors as `status` strings like "414 Unknown User Agent".
        if let status = value["status"]?.stringValue, !status.hasPrefix("2") {
            throw EngineError.httpError(statusCode: Int(status.prefix(3)) ?? 0)
        }
        return value
    }
}
