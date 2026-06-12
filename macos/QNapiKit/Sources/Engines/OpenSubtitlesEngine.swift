import Foundation
import QNapiCore

/// Configuration for the OpenSubtitles REST API (api.opensubtitles.com v1).
public struct OpenSubtitlesConfiguration: Sendable {
    public let apiKey: String
    public let userAgent: String
    public let credentials: EngineCredentials?

    public init(
        apiKey: String,
        userAgent: String = "QNapi v\(QNapiCore.version)",
        credentials: EngineCredentials? = nil
    ) {
        self.apiKey = apiKey
        self.userAgent = userAgent
        self.credentials = credentials
    }
}

/// OpenSubtitles via the modern REST API. An actor because it lazily logs
/// in and caches the JWT token across calls when credentials are present.
public actor OpenSubtitlesEngine: SubtitleEngine {
    static let baseURL = URL(string: "https://api.opensubtitles.com/api/v1")!

    public nonisolated let metadata = EngineMetadata(
        id: "OpenSubtitles",
        displayName: "OpenSubtitles",
        websiteURL: URL(string: "https://www.opensubtitles.com")!,
        registrationURL: URL(string: "https://www.opensubtitles.com/users/sign_up")!,
        supportsCredentials: true)

    private let configuration: OpenSubtitlesConfiguration
    private let session: URLSession
    private var token: String?

    public init(configuration: OpenSubtitlesConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: - SubtitleEngine

    public func search(file: MovieFileDescriptor, language: SubtitleLanguage) async throws
        -> [FoundSubtitle]
    {
        guard let movieHash = file.openSubtitlesHash else {
            throw EngineError.missingHash
        }

        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "languages", value: language.twoLetter),
            URLQueryItem(name: "moviehash", value: movieHash),
            URLQueryItem(name: "query", value: file.baseName),
        ]

        let data = try await send(request: makeRequest(url: components.url!))
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)

        return response.data.compactMap { item -> FoundSubtitle? in
            guard let fileInfo = item.attributes.files.first else { return nil }
            let release = item.attributes.release ?? file.baseName
            let hashMatched = item.attributes.moviehashMatch ?? false
            var comment = "downloads: \(item.attributes.downloadCount ?? 0)"
            if let fps = item.attributes.fps, fps > 0 {
                comment += ", fps: \(fps)"
            }
            return FoundSubtitle(
                engineID: metadata.id,
                language: language,
                title: fileInfo.fileName ?? release,
                comment: comment,
                formatExtension: "srt",
                resolution: hashMatched ? .good : .unknown,
                handle: String(fileInfo.fileId))
        }
        .sorted { $0.resolution > $1.resolution }
    }

    public func download(_ subtitle: FoundSubtitle, to directory: URL) async throws -> URL {
        guard let fileId = Int(subtitle.handle) else {
            throw EngineError.invalidResponse
        }

        if token == nil, let credentials = configuration.credentials {
            token = try await login(credentials)
        }

        var request = makeRequest(url: Self.baseURL.appendingPathComponent("download"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(["file_id": fileId])

        let data = try await send(request: request)
        let response = try JSONDecoder().decode(DownloadResponse.self, from: data)
        guard let link = URL(string: response.link) else {
            throw EngineError.invalidResponse
        }

        let (subtitleData, _) = try await session.data(from: link)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = response.fileName ?? "\(subtitle.title).srt"
        let target = directory.appendingPathComponent(fileName)
        try subtitleData.write(to: target)
        return target
    }

    // MARK: - Internals

    private func login(_ credentials: EngineCredentials) async throws -> String {
        var request = makeRequest(url: Self.baseURL.appendingPathComponent("login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "username": credentials.username,
            "password": credentials.password,
        ])

        do {
            let data = try await send(request: request)
            let response = try JSONDecoder().decode(LoginResponse.self, from: data)
            return response.token
        } catch {
            throw EngineError.authenticationFailed
        }
    }

    private nonisolated func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(configuration.apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.invalidResponse
        }
        switch http.statusCode {
        case 200, 201: return data
        case 401, 403: throw EngineError.authenticationFailed
        case 406: throw EngineError.downloadQuotaExceeded
        default: throw EngineError.httpError(statusCode: http.statusCode)
        }
    }

    // MARK: - Response models

    private struct SearchResponse: Decodable {
        let data: [SearchItem]
    }

    private struct SearchItem: Decodable {
        let attributes: Attributes
    }

    private struct Attributes: Decodable {
        let release: String?
        let fps: Double?
        let moviehashMatch: Bool?
        let downloadCount: Int?
        let files: [FileInfo]

        enum CodingKeys: String, CodingKey {
            case release, fps
            case moviehashMatch = "moviehash_match"
            case downloadCount = "download_count"
            case files
        }
    }

    private struct FileInfo: Decodable {
        let fileId: Int
        let fileName: String?

        enum CodingKeys: String, CodingKey {
            case fileId = "file_id"
            case fileName = "file_name"
        }
    }

    private struct DownloadResponse: Decodable {
        let link: String
        let fileName: String?

        enum CodingKeys: String, CodingKey {
            case link
            case fileName = "file_name"
        }
    }

    private struct LoginResponse: Decodable {
        let token: String
    }
}
