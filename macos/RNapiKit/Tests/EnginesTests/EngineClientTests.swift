import Foundation
import RNapiCore
import Testing

@testable import Engines

private let movie = MovieFileDescriptor(
    url: URL(fileURLWithPath: "/tmp/Some.Movie.2024.mkv"),
    fileSize: 1_234_567,
    openSubtitlesHash: "df1f5f9fe0234d40",
    napiProjektChecksum: "1864c7bdedbe7c28714025ff5a0d871a")

private let polish = SubtitleLanguage("pl")!
private let english = SubtitleLanguage("en")!

/// A payload that passes the engines' 7z-magic sanity check.
private func fake7zArchive(_ tail: String) -> Data {
    var data = Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
    data.append(Data(tail.utf8))
    return data
}

/// Base64 of "1\n00:03:14,400 --> 00:03:20,400\nWitaj\n".
private let napiSubtitleBase64 = "MQowMDowMzoxNCw0MDAgLS0+IDAwOjAzOjIwLDQwMApXaXRhago="

private func napiSuccessXML(content: String) -> Data {
    Data(
        """
        <?xml version="1.0"?>
        <result><status>success</status><subtitles>\
        <id>1864c7bdedbe7c28714025ff5a0d871a</id>\
        <author>kat</author>\
        <content><![CDATA[\(content)]]></content>\
        </subtitles></result>
        """.utf8)
}

@Suite(.serialized) struct NapiProjektEngineTests {
    @Test func searchPostsApi3FormAndStashesDecodedSubtitle() async throws {
        MockURLProtocol.setHandler(hosts: ["napiprojekt.pl"]) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path() == "/api/api-napiprojekt3.php")
            let body = String(decoding: requestBody(of: request), as: UTF8.self)
            #expect(body.contains("mode=1"))
            #expect(body.contains("downloaded_subtitles_id=1864c7bdedbe7c28714025ff5a0d871a"))
            #expect(body.contains("downloaded_subtitles_lang=PL"))
            #expect(body.contains("downloaded_subtitles_txt=1"))
            return (httpResponse(for: request), napiSuccessXML(content: napiSubtitleBase64))
        }

        let engine = NapiProjektEngine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)

        #expect(results.count == 1)
        #expect(results[0].engineID == "NapiProjekt")
        #expect(results[0].title == "Some.Movie.2024")
        #expect(results[0].comment == "author: kat")
        // The handle points at the stashed, already decoded subtitle text.
        let stashed = try String(
            contentsOf: URL(fileURLWithPath: results[0].handle), encoding: .utf8)
        #expect(stashed == "1\n00:03:14,400 --> 00:03:20,400\nWitaj\n")
    }

    @Test func englishIsSpelledENG() {
        #expect(NapiProjektEngine.languageParameter(english) == "ENG")
        #expect(NapiProjektEngine.languageParameter(polish) == "PL")
    }

    @Test func missResponseMeansNoSubtitles() async throws {
        MockURLProtocol.setHandler(hosts: ["napiprojekt.pl"]) { request in
            let xml = """
                <?xml version="1.0"?>
                <result><response_time>0.005 s.</response_time></result>
                """
            return (httpResponse(for: request), Data(xml.utf8))
        }
        let engine = NapiProjektEngine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)
        #expect(results.isEmpty)
    }

    @Test func htmlErrorPageMeansNoSubtitles() async throws {
        MockURLProtocol.setHandler(hosts: ["napiprojekt.pl"]) { request in
            (httpResponse(for: request), Data("<html>service hiccup</html>".utf8))
        }
        let engine = NapiProjektEngine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)
        #expect(results.isEmpty)
    }

    @Test func downloadCopiesStashedSubtitle() async throws {
        let stash = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnapi-np-test-\(UUID().uuidString).txt")
        try Data("subtitle text".utf8).write(to: stash)
        defer { try? FileManager.default.removeItem(at: stash) }

        let engine = NapiProjektEngine(session: MockURLProtocol.makeSession())
        let found = FoundSubtitle(
            engineID: "NapiProjekt", language: polish, title: "x",
            formatExtension: "txt", resolution: .unknown, handle: stash.path)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnapi-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try await engine.download(found, to: dir)
        #expect(try String(contentsOf: url, encoding: .utf8) == "subtitle text")
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
            payload.append(fake7zArchive("archive-bytes"))
            return (httpResponse(for: request), payload)
        }

        let engine = Napisy24Engine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)

        #expect(results.count == 1)
        let stashed = try Data(contentsOf: URL(fileURLWithPath: results[0].handle))
        #expect(stashed == fake7zArchive("archive-bytes"))
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
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("RNapi") == true)
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
            .appendingPathComponent("rnapi-test-\(UUID().uuidString)")
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
