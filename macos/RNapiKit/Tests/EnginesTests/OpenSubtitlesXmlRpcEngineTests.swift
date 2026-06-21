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

private func rpcResponse(_ innerValue: String) -> Data {
    Data(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <methodResponse><params><param><value>\(innerValue)</value></param></params></methodResponse>
        """.utf8)
}

private let loginResponse = rpcResponse(
    """
    <struct>
    <member><name>token</name><value><string>test-token</string></value></member>
    <member><name>status</name><value><string>200 OK</string></value></member>
    </struct>
    """)

private let searchResponse = rpcResponse(
    """
    <struct>
    <member><name>status</name><value><string>200 OK</string></value></member>
    <member><name>data</name><value><array><data>
    <value><struct>
    <member><name>IDSubtitleFile</name><value><string>1952039423</string></value></member>
    <member><name>SubFileName</name><value><string>Some.Movie.2024.srt</string></value></member>
    <member><name>SubBad</name><value><string>0</string></value></member>
    <member><name>MovieReleaseName</name><value><string>Some.Movie.2024</string></value></member>
    <member><name>SubAuthorComment</name><value><string>nice</string></value></member>
    </struct></value>
    <value><struct>
    <member><name>IDSubtitleFile</name><value><string>666</string></value></member>
    <member><name>SubFileName</name><value><string>Other.Cut.txt</string></value></member>
    <member><name>SubBad</name><value><string>1</string></value></member>
    <member><name>MovieReleaseName</name><value><string>Other.Cut</string></value></member>
    <member><name>SubAuthorComment</name><value><string></string></value></member>
    </struct></value>
    </data></array></value></member>
    </struct>
    """)

/// `data` is boolean false when the service has nothing.
private let emptySearchResponse = rpcResponse(
    """
    <struct>
    <member><name>status</name><value><string>200 OK</string></value></member>
    <member><name>data</name><value><boolean>0</boolean></value></member>
    </struct>
    """)

/// Gzip of "1\n00:00:01,000 --> 00:00:02,000\nWitaj swiecie\n".
private let gzippedSubtitle =
    "H4sIAHb/K2oAAzPkMjCwAiFDHQMDAwVdXTsFqIARSIArPLMkMUuhuDwzNTkzlQsA5tcWoy4AAAA="
private let subtitleText = "1\n00:00:01,000 --> 00:00:02,000\nWitaj swiecie\n"

private func downloadResponse(base64: String) -> Data {
    rpcResponse(
        """
        <struct>
        <member><name>status</name><value><string>200 OK</string></value></member>
        <member><name>data</name><value><array><data>
        <value><struct>
        <member><name>idsubtitlefile</name><value><string>1952039423</string></value></member>
        <member><name>data</name><value><string>\(base64)</string></value></member>
        </struct></value>
        </data></array></value></member>
        </struct>
        """)
}

private func methodName(of request: URLRequest) -> String {
    let body = String(decoding: requestBody(of: request), as: UTF8.self)
    guard let start = body.range(of: "<methodName>"),
          let end = body.range(of: "</methodName>")
    else { return "" }
    return String(body[start.upperBound..<end.lowerBound])
}

@Suite(.serialized) struct OpenSubtitlesXmlRpcEngineTests {
    @Test func anonymousLoginThenSearchMapsResults() async throws {
        MockURLProtocol.setHandler(hosts: ["api.opensubtitles.org"]) { request in
            let body = String(decoding: requestBody(of: request), as: UTF8.self)
            switch methodName(of: request) {
            case "LogIn":
                // Anonymous login with the registered QNapi user agent.
                #expect(body.contains("<string>QNapi v0.2.4-snapshot</string>"))
                return (httpResponse(for: request), loginResponse)
            case "SearchSubtitles":
                #expect(body.contains("<string>test-token</string>"))
                #expect(body.contains("<string>pol</string>"))
                #expect(body.contains("<string>df1f5f9fe0234d40</string>"))
                #expect(body.contains("<string>1234567</string>"))
                return (httpResponse(for: request), searchResponse)
            default:
                throw URLError(.badURL)
            }
        }

        let engine = OpenSubtitlesXmlRpcEngine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)

        #expect(results.count == 2)
        // Hash + name match first, bad subtitle last.
        #expect(results[0].handle == "1952039423")
        #expect(results[0].resolution == .good)
        #expect(results[0].formatExtension == "srt")
        #expect(results[0].comment == "nice")
        #expect(results[1].resolution == .bad)
        #expect(results[1].formatExtension == "txt")
    }

    @Test func booleanFalseDataMeansNoResults() async throws {
        MockURLProtocol.setHandler(hosts: ["api.opensubtitles.org"]) { request in
            switch methodName(of: request) {
            case "LogIn": return (httpResponse(for: request), loginResponse)
            default: return (httpResponse(for: request), emptySearchResponse)
            }
        }

        let engine = OpenSubtitlesXmlRpcEngine(session: MockURLProtocol.makeSession())
        let results = try await engine.search(file: movie, language: polish)
        #expect(results.isEmpty)
    }

    @Test func downloadDecodesBase64Gzip() async throws {
        MockURLProtocol.setHandler(hosts: ["api.opensubtitles.org"]) { request in
            switch methodName(of: request) {
            case "LogIn":
                return (httpResponse(for: request), loginResponse)
            case "DownloadSubtitles":
                let body = String(decoding: requestBody(of: request), as: UTF8.self)
                #expect(body.contains("<string>1952039423</string>"))
                return (httpResponse(for: request), downloadResponse(base64: gzippedSubtitle))
            default:
                throw URLError(.badURL)
            }
        }

        let engine = OpenSubtitlesXmlRpcEngine(session: MockURLProtocol.makeSession())
        let found = FoundSubtitle(
            engineID: "OpenSubtitles", language: polish, title: "Some.Movie.2024",
            formatExtension: "srt", resolution: .good, handle: "1952039423")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnapi-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try await engine.download(found, to: dir)
        #expect(url.pathExtension == "srt")
        #expect(try String(contentsOf: url, encoding: .utf8) == subtitleText)
    }

    @Test func badStatusFailsLogin() async throws {
        MockURLProtocol.setHandler(hosts: ["api.opensubtitles.org"]) { request in
            let response = rpcResponse(
                """
                <struct>
                <member><name>status</name><value><string>414 Unknown User Agent</string></value></member>
                </struct>
                """)
            return (httpResponse(for: request), response)
        }

        let engine = OpenSubtitlesXmlRpcEngine(session: MockURLProtocol.makeSession())
        await #expect(throws: EngineError.self) {
            _ = try await engine.search(file: movie, language: polish)
        }
    }
}

@Suite struct GzipTests {
    @Test func inflatesGzipStream() throws {
        let compressed = try #require(Data(base64Encoded: gzippedSubtitle))
        let inflated = try Gzip.inflate(compressed)
        #expect(String(decoding: inflated, as: UTF8.self) == subtitleText)
    }

    @Test func rejectsNonGzipData() {
        #expect(throws: GzipError.self) {
            _ = try Gzip.inflate(Data("definitely not gzip data here".utf8))
        }
    }
}

@Suite struct XmlRpcParserTests {
    @Test func parsesNestedStructuresAndTypes() throws {
        let value = try XmlRpcResponseParser.parse(searchResponse)
        let items = try #require(value["data"]?.arrayValue)
        #expect(items.count == 2)
        #expect(items[0]["IDSubtitleFile"]?.stringValue == "1952039423")
        #expect(value["status"]?.stringValue == "200 OK")
    }

    @Test func untypedValueIsString() throws {
        let value = try XmlRpcResponseParser.parse(rpcResponse("plain"))
        #expect(value.stringValue == "plain")
    }

    @Test func faultThrows() {
        let fault = Data(
            """
            <?xml version="1.0"?><methodResponse><fault><value><struct>
            <member><name>faultCode</name><value><int>4</int></value></member>
            <member><name>faultString</name><value><string>Too many requests</string></value></member>
            </struct></value></fault></methodResponse>
            """.utf8)
        #expect(throws: XmlRpcError.self) {
            _ = try XmlRpcResponseParser.parse(fault)
        }
    }
}
