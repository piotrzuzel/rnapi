import Foundation
import RNapiCore
import Testing

@testable import Engines

/// Opt-in tests that hit the real services. Excluded from normal runs:
///
///     RNAPI_LIVE_TESTS=1 swift test --filter LiveEngineTests
///
/// Optional extras:
///   RNAPI_LIVE_MOVIE=/path/to/movie.mkv  — full search+download round-trip
///   RNAPI_OS_API_KEY=...                 — enables the OpenSubtitles tests
private let liveTestsEnabled = ProcessInfo.processInfo.environment["RNAPI_LIVE_TESTS"] != nil
private let liveMoviePath = ProcessInfo.processInfo.environment["RNAPI_LIVE_MOVIE"]
private let osApiKey = ProcessInfo.processInfo.environment["RNAPI_OS_API_KEY"]

/// A descriptor whose hashes match no real movie — services must answer
/// with their well-formed "nothing found" shape, not an error.
private let bogusMovie = MovieFileDescriptor(
    url: URL(fileURLWithPath: "/tmp/rnapi-live-bogus.mkv"),
    fileSize: 734_003_200,
    openSubtitlesHash: "0123456789abcdef",
    napiProjektChecksum: "0123456789abcdef0123456789abcdef")

private let polish = SubtitleLanguage("pl")!

private func liveDescriptor() throws -> MovieFileDescriptor {
    let path = try #require(liveMoviePath, "set RNAPI_LIVE_MOVIE for the round-trip tests")
    return try MovieFileDescriptor.hashing(url: URL(fileURLWithPath: path))
}

private func downloadDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("rnapi-live-\(UUID().uuidString)")
}

@Suite(.enabled(if: liveTestsEnabled), .serialized)
struct LiveEngineTests {
    @Test func napiProjektAnswersNoSubtitlesForBogusChecksum() async throws {
        let results = try await NapiProjektEngine().search(file: bogusMovie, language: polish)
        #expect(results.isEmpty)
    }

    @Test func napisy24AnswersNoSubtitlesForBogusHash() async throws {
        let results = try await Napisy24Engine().search(file: bogusMovie, language: polish)
        #expect(results.isEmpty)
    }

    @Test func openSubtitlesXmlRpcAnonymousLoginAnswersForBogusHash() async throws {
        // Exercises the anonymous LogIn + SearchSubtitles round trip.
        let engine = OpenSubtitlesXmlRpcEngine()
        let results = try await engine.search(file: bogusMovie, language: polish)
        #expect(results.isEmpty)
    }

    @Test(.enabled(if: osApiKey != nil))
    func openSubtitlesSearchResponseDecodes() async throws {
        let engine = OpenSubtitlesEngine(
            configuration: OpenSubtitlesConfiguration(apiKey: osApiKey ?? ""))
        // Bogus hash but a real-word query — exercises auth and decoding.
        let results = try await engine.search(file: bogusMovie, language: polish)
        // Any count is fine; reaching here means HTTP 200 + valid JSON.
        _ = results
    }

    @Test(.enabled(if: liveMoviePath != nil))
    func napiProjektRoundTripDownloadsRealSubtitles() async throws {
        let descriptor = try liveDescriptor()
        let engine = NapiProjektEngine()
        let results = try await engine.search(file: descriptor, language: polish)
        try #require(!results.isEmpty, "service has no subtitles for this movie")

        let dir = downloadDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = try await engine.download(results[0], to: dir)
        let size = try FileManager.default.attributesOfItem(atPath: subtitle.path)[.size] as? Int
        #expect((size ?? 0) > 0)
    }

    @Test(.enabled(if: liveMoviePath != nil))
    func napisy24RoundTripDownloadsRealSubtitles() async throws {
        let descriptor = try liveDescriptor()
        let engine = Napisy24Engine()
        let results = try await engine.search(file: descriptor, language: polish)
        try #require(!results.isEmpty, "service has no subtitles for this movie")

        let dir = downloadDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = try await engine.download(results[0], to: dir)
        let size = try FileManager.default.attributesOfItem(atPath: subtitle.path)[.size] as? Int
        #expect((size ?? 0) > 0)
    }

    @Test(.enabled(if: liveMoviePath != nil))
    func openSubtitlesXmlRpcRoundTripDownloadsRealSubtitles() async throws {
        let descriptor = try liveDescriptor()
        let engine = OpenSubtitlesXmlRpcEngine()
        let results = try await engine.search(file: descriptor, language: polish)
        try #require(!results.isEmpty, "service has no subtitles for this movie")

        let dir = downloadDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = try await engine.download(results[0], to: dir)
        let size = try FileManager.default.attributesOfItem(atPath: subtitle.path)[.size] as? Int
        #expect((size ?? 0) > 0)
    }

    @Test(.enabled(if: liveMoviePath != nil && osApiKey != nil))
    func openSubtitlesRoundTripDownloadsRealSubtitles() async throws {
        let descriptor = try liveDescriptor()
        let engine = OpenSubtitlesEngine(
            configuration: OpenSubtitlesConfiguration(apiKey: osApiKey ?? ""))
        let results = try await engine.search(file: descriptor, language: polish)
        try #require(!results.isEmpty, "service has no subtitles for this movie")

        let dir = downloadDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = try await engine.download(results[0], to: dir)
        let contents = try String(contentsOf: subtitle, encoding: .utf8)
        #expect(!contents.isEmpty)
    }
}
