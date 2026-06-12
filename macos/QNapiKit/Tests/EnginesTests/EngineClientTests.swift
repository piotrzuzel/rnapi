import Foundation
import QNapiCore
import Testing

@testable import Engines

private let movie = MovieFileDescriptor(
    url: URL(fileURLWithPath: "/tmp/Some.Movie.2024.mkv"),
    fileSize: 1_234_567,
    openSubtitlesHash: "df1f5f9fe0234d40",
    napiProjektChecksum: "1864c7bdedbe7c28714025ff5a0d871a")

private let polish = SubtitleLanguage("pl")!
private let english = SubtitleLanguage("en")!

@Suite(.serialized) struct NapiProjektEngineTests {
    @Test func searchBuildsCorrectRequestAndReturnsResult() async throws {
        MockURLProtocol.setHandler(hosts: ["www.napiprojekt.pl"]) { request in
            let components = URLComponents(
                url: request.url!, resolvingAgainstBaseURL: false)!
            let query = Dictionary(
                uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
            #expect(components.host == "www.napiprojekt.pl")
            #expect(query["l"] == "PL")
            #expect(query["f"] == "1864c7bdedbe7c28714025ff5a0d871a")
            #expect(query["t"] == "88805")
            #expect(query["napios"] == "Mac OS X")
            return (httpResponse(for: request), Data("7z-archive-bytes".utf8))
        }

        let engine = NapiProjektEngine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)

        #expect(results.count == 1)
        #expect(results[0].engineID == "NapiProjekt")
        #expect(results[0].title == "Some.Movie.2024")
        // The handle points at the stashed archive.
        let stashed = try Data(contentsOf: URL(fileURLWithPath: results[0].handle))
        #expect(stashed == Data("7z-archive-bytes".utf8))
    }

    @Test func englishIsSpelledENG() {
        #expect(NapiProjektEngine.languageParameter(english) == "ENG")
        #expect(NapiProjektEngine.languageParameter(polish) == "PL")
    }

    @Test func npcMarkerMeansNoSubtitles() async throws {
        MockURLProtocol.setHandler(hosts: ["www.napiprojekt.pl"]) { request in
            (httpResponse(for: request), Data("NPc: no subtitles".utf8))
        }
        let engine = NapiProjektEngine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)
        #expect(results.isEmpty)
    }

    @Test func downloadExtractsWithHardcodedPassword() async throws {
        let extractor = FakeArchiveExtractor(
            fileNames: ["napisy.srt"], expectedPassword: "iBlm8NTigvru0Jr0")
        let engine = NapiProjektEngine(
            session: MockURLProtocol.makeSession(), extractor: extractor)
        let found = FoundSubtitle(
            engineID: "NapiProjekt", language: polish, title: "x",
            formatExtension: "txt", resolution: .unknown, handle: "/tmp/fake.7z")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qnapi-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try await engine.download(found, to: dir)
        #expect(url.lastPathComponent == "napisy.srt")
    }
}

@Suite(.serialized) struct Napisy24EngineTests {
    @Test func rejectsNonPolishWithoutNetworkCall() async throws {
        MockURLProtocol.setHandler(hosts: ["napisy24.pl"]) { _ in
            Issue.record("must not hit the network for non-Polish languages")
            throw URLError(.badURL)
        }
        let engine = Napisy24Engine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: english)
        #expect(results.isEmpty)
    }

    @Test func parsesOK2FramingAndPostsAgentForm() async throws {
        MockURLProtocol.setHandler(hosts: ["napisy24.pl"]) { request in
            #expect(request.httpMethod == "POST")
            let body = String(decoding: requestBody(of: request), as: UTF8.self)
            #expect(body.contains("postAction=CheckSub"))
            #expect(body.contains("ua=tantalosus"))
            #expect(body.contains("fh=df1f5f9fe0234d40"))
            #expect(body.contains("fs=1234567"))
            var payload = Data("OK-2||".utf8)
            payload.append(Data("archive-bytes".utf8))
            return (httpResponse(for: request), payload)
        }

        let engine = Napisy24Engine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)

        #expect(results.count == 1)
        let stashed = try Data(contentsOf: URL(fileURLWithPath: results[0].handle))
        #expect(stashed == Data("archive-bytes".utf8))
    }

    @Test func nonOKResponseMeansNoResults() async throws {
        MockURLProtocol.setHandler(hosts: ["napisy24.pl"]) { request in
            (httpResponse(for: request), Data("brak danych".utf8))
        }
        let engine = Napisy24Engine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)
        #expect(results.isEmpty)
    }
}

@Suite(.serialized) struct OpenSubtitlesEngineTests {
    private let config = OpenSubtitlesConfiguration(apiKey: "test-key")

    private let searchJSON = """
        {
          "data": [
            {
              "attributes": {
                "release": "Some.Movie.2024.1080p",
                "fps": 23.976,
                "moviehash_match": false,
                "download_count": 100,
                "files": [{"file_id": 111, "file_name": "other.srt"}]
              }
            },
            {
              "attributes": {
                "release": "Some.Movie.2024.WEB",
                "moviehash_match": true,
                "download_count": 5000,
                "files": [{"file_id": 222, "file_name": "matched.srt"}]
              }
            }
          ]
        }
        """

    @Test func searchSendsApiKeyAndSortsHashMatchesFirst() async throws {
        let json = searchJSON
        MockURLProtocol.setHandler(hosts: ["api.opensubtitles.com"]) { request in
            #expect(request.value(forHTTPHeaderField: "Api-Key") == "test-key")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("QNapi") == true)
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            #expect(
                components.queryItems?.contains(
                    URLQueryItem(name: "moviehash", value: "df1f5f9fe0234d40")) == true)
            return (httpResponse(for: request), Data(json.utf8))
        }

        let engine = OpenSubtitlesEngine(
            configuration: config, session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)

        #expect(results.count == 2)
        #expect(results[0].resolution == .good)
        #expect(results[0].title == "matched.srt")
        #expect(results[0].handle == "222")
        #expect(results[1].resolution == .unknown)
    }

    @Test func downloadFollowsLinkAndWritesFile() async throws {
        MockURLProtocol.setHandler(hosts: ["api.opensubtitles.com", "example.com"]) { request in
            switch request.url!.path {
            case "/api/v1/download":
                let body = requestBody(of: request)
                let parsed = try JSONDecoder().decode([String: Int].self, from: body)
                #expect(parsed["file_id"] == 222)
                let response = """
                    {"link": "https://example.com/sub/222.srt", "file_name": "matched.srt"}
                    """
                return (httpResponse(for: request), Data(response.utf8))
            case "/sub/222.srt":
                return (httpResponse(for: request), Data("1\n00:00:01,000 --> 00:00:02,000\nHi\n".utf8))
            default:
                throw URLError(.badURL)
            }
        }

        let engine = OpenSubtitlesEngine(
            configuration: config, session: MockURLProtocol.makeSession())
        let found = FoundSubtitle(
            engineID: "OpenSubtitles", language: polish, title: "x",
            formatExtension: "srt", resolution: .good, handle: "222")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qnapi-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try await engine.download(found, to: dir)
        #expect(url.lastPathComponent == "matched.srt")
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("Hi"))
    }

    @Test func quotaExhaustionThrows() async throws {
        MockURLProtocol.setHandler(hosts: ["api.opensubtitles.com"]) { request in
            (httpResponse(for: request, status: 406), Data())
        }
        let engine = OpenSubtitlesEngine(
            configuration: config, session: MockURLProtocol.makeSession())
        let found = FoundSubtitle(
            engineID: "OpenSubtitles", language: polish, title: "x",
            formatExtension: "srt", resolution: .good, handle: "1")

        await #expect(throws: EngineError.self) {
            _ = try await engine.download(found, to: FileManager.default.temporaryDirectory)
        }
    }
}
