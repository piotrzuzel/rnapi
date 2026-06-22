import Engines
import Foundation
import MediaInfo
import RQNapiCore
import Testing

@testable import DownloadPipeline

// MARK: - Fakes

/// Engine returning canned results; "downloads" by writing a fixed SRT.
private struct FakeEngine: SubtitleEngine {
    let metadata: EngineMetadata
    let results: [FoundSubtitle]
    let searchedLanguages: Mailbox<String>?

    init(id: String, results: [FoundSubtitle], searchedLanguages: Mailbox<String>? = nil) {
        self.metadata = EngineMetadata(
            id: id, displayName: id, websiteURL: URL(string: "https://example.com")!)
        self.results = results
        self.searchedLanguages = searchedLanguages
    }

    func search(file: MovieFileDescriptor, language: SubtitleLanguage) async throws
        -> [FoundSubtitle]
    {
        searchedLanguages?.append("\(metadata.id):\(language.twoLetter)")
        return results.filter { $0.language == language }
    }

    func download(_ subtitle: FoundSubtitle, to directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("downloaded.srt")
        try Data("1\n00:00:01,000 --> 00:00:02,000\nzażółć\n".utf8).write(to: url)
        return url
    }
}

/// Thread-safe accumulator usable from Sendable contexts.
final class Mailbox<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []

    func append(_ item: Element) { lock.withLock { items.append(item) } }
    var contents: [Element] { lock.withLock { items } }
}

private struct FixedMovieInfo: MovieInfoProvider {
    let frameRate: Double
    func movieInfo(for url: URL) async -> MovieInfo? {
        MovieInfo(frameRate: frameRate, durationSeconds: 5400)
    }
}

private struct RecordingSelector: SubtitleSelector {
    let invoked: Mailbox<URL>
    let pick: Int?

    func choose(from subtitles: [FoundSubtitle], movie: URL) async -> FoundSubtitle? {
        invoked.append(movie)
        guard let pick else { return nil }
        return subtitles[pick]
    }
}

private let polish = SubtitleLanguage("pl")!
private let english = SubtitleLanguage("en")!

private func found(
    _ engine: String, language: SubtitleLanguage = polish,
    resolution: SubtitleResolution = .unknown
) -> FoundSubtitle {
    FoundSubtitle(
        engineID: engine, language: language, title: "result",
        formatExtension: "srt", resolution: resolution, handle: "h")
}

/// Creates a movie file in a fresh temp directory.
private func makeMovie() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("rqnapi-pipeline-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let movie = dir.appendingPathComponent("Movie.Title.2024.mkv")
    try Data(repeating: 7, count: 200_000).write(to: movie)
    return movie
}

private func collectEvents(
    _ pipeline: SubtitleDownloadPipeline, movies: [URL]
) async -> [PipelineEvent] {
    var events: [PipelineEvent] = []
    for await event in pipeline.run(movies: movies) {
        events.append(event)
    }
    return events
}

// MARK: - Tests

@Suite struct PipelineFlowTests {
    @Test func happyPathPlacesSubtitleNextToMovie() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.deletingLastPathComponent()) }

        let pipeline = SubtitleDownloadPipeline(
            engines: [FakeEngine(id: "A", results: [found("A", resolution: .good)])],
            movieInfoProvider: FixedMovieInfo(frameRate: 25),
            configuration: PipelineConfiguration(language: polish))

        let events = await collectEvents(pipeline, movies: [movie])

        let completed = events.compactMap { event -> URL? in
            if case .fileCompleted(_, let subtitle) = event { return subtitle }
            return nil
        }
        #expect(completed.count == 1)
        let expected = movie.deletingLastPathComponent().appendingPathComponent("Movie.Title.2024.srt")
        #expect(completed.first == expected)
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }

    @Test func noResultsReportsFailure() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.deletingLastPathComponent()) }

        let pipeline = SubtitleDownloadPipeline(
            engines: [FakeEngine(id: "A", results: [])],
            configuration: PipelineConfiguration(language: polish))

        let events = await collectEvents(pipeline, movies: [movie])
        let failures = events.compactMap { event -> PipelineFailure? in
            if case .fileFailed(_, let failure) = event { return failure }
            return nil
        }
        #expect(failures == [.noSubtitlesFound])
    }

    @Test func breakIfFoundStopsAfterFirstEngineWithResults() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.deletingLastPathComponent()) }

        let searched = Mailbox<String>()
        let pipeline = SubtitleDownloadPipeline(
            engines: [
                FakeEngine(id: "A", results: [found("A")], searchedLanguages: searched),
                FakeEngine(id: "B", results: [found("B")], searchedLanguages: searched),
            ],
            configuration: PipelineConfiguration(language: polish, searchPolicy: .breakIfFound))

        _ = await collectEvents(pipeline, movies: [movie])
        #expect(searched.contents == ["A:pl"])
    }

    @Test func backupLanguageSearchedWhenPrimaryEmpty() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.deletingLastPathComponent()) }

        let searched = Mailbox<String>()
        let pipeline = SubtitleDownloadPipeline(
            engines: [
                FakeEngine(
                    id: "A", results: [found("A", language: english)], searchedLanguages: searched)
            ],
            configuration: PipelineConfiguration(
                language: polish, backupLanguage: english, searchPolicy: .breakIfFound))

        let events = await collectEvents(pipeline, movies: [movie])
        #expect(searched.contents == ["A:pl", "A:en"])
        #expect(events.contains { if case .fileCompleted = $0 { true } else { false } })
    }

    @Test func selectorConsultedWhenSeveralUncertainResults() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.deletingLastPathComponent()) }

        let invoked = Mailbox<URL>()
        let pipeline = SubtitleDownloadPipeline(
            engines: [FakeEngine(id: "A", results: [found("A"), found("A")])],
            selector: RecordingSelector(invoked: invoked, pick: 1),
            configuration: PipelineConfiguration(
                language: polish, downloadPolicy: .showListIfNeeded))

        _ = await collectEvents(pipeline, movies: [movie])
        #expect(invoked.contents.count == 1)
    }

    @Test func selectorSkippedWhenHashMatchExists() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.deletingLastPathComponent()) }

        let invoked = Mailbox<URL>()
        let pipeline = SubtitleDownloadPipeline(
            engines: [
                FakeEngine(id: "A", results: [found("A"), found("A", resolution: .good)])
            ],
            selector: RecordingSelector(invoked: invoked, pick: 0),
            configuration: PipelineConfiguration(
                language: polish, downloadPolicy: .showListIfNeeded))

        _ = await collectEvents(pipeline, movies: [movie])
        #expect(invoked.contents.isEmpty)
    }

    @Test func cancelledSelectionFailsFile() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.deletingLastPathComponent()) }

        let pipeline = SubtitleDownloadPipeline(
            engines: [FakeEngine(id: "A", results: [found("A"), found("A")])],
            selector: RecordingSelector(invoked: Mailbox(), pick: nil),
            configuration: PipelineConfiguration(
                language: polish, downloadPolicy: .alwaysShowList))

        let events = await collectEvents(pipeline, movies: [movie])
        let failures = events.compactMap { event -> PipelineFailure? in
            if case .fileFailed(_, let failure) = event { return failure }
            return nil
        }
        #expect(failures == [.selectionCancelled])
    }
}

@Suite struct MatcherTests {
    private func makeFiles() throws -> (movie: URL, subtitle: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rqnapi-matcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let movie = dir.appendingPathComponent("Film.mkv")
        try Data("movie".utf8).write(to: movie)
        let subtitle = dir.appendingPathComponent("tmp-subtitle.srt")
        try Data("subtitle-content".utf8).write(to: subtitle)
        return (movie, subtitle, dir)
    }

    @Test func placesSubtitleWithMovieBaseName() throws {
        let (movie, subtitle, dir) = try makeFiles()
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = try SubtitleMatcher(configuration: .init())
            .match(subtitle: subtitle, movie: movie)
        #expect(target.lastPathComponent == "Film.srt")
        #expect(try String(contentsOf: target, encoding: .utf8) == "subtitle-content")
    }

    @Test func replacesExistingSubtitleWithoutLeavingACopy() throws {
        let (movie, subtitle, dir) = try makeFiles()
        defer { try? FileManager.default.removeItem(at: dir) }

        let existing = dir.appendingPathComponent("Film.srt")
        try Data("old".utf8).write(to: existing)

        try SubtitleMatcher(configuration: .init())
            .match(subtitle: subtitle, movie: movie)

        #expect(!FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("Film_copy.srt").path))
        #expect(try String(contentsOf: existing, encoding: .utf8) == "subtitle-content")
    }

    @Test func leavesOnlyOneSubtitleClearingOtherExtensionsAndLegacyCopies() throws {
        let (movie, subtitle, dir) = try makeFiles()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Leftovers from earlier runs: a different extension and a _copy backup.
        for name in ["Film.txt", "Film.sub", "Film_copy.srt"] {
            try Data("old".utf8).write(to: dir.appendingPathComponent(name))
        }

        let target = try SubtitleMatcher(configuration: .init())
            .match(subtitle: subtitle, movie: movie)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { name in
                name.hasPrefix("Film")
                    && ["srt", "sub", "txt"].contains((name as NSString).pathExtension)
            }
            .sorted()
        #expect(remaining == ["Film.srt"])
        #expect(target.lastPathComponent == "Film.srt")
    }

    @Test func postProcessingFormatDrivesExtension() throws {
        let (movie, subtitle, dir) = try makeFiles()
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = try SubtitleMatcher(
            configuration: .init(postProcessingEnabled: true, targetFormatName: "microdvd")
        ).match(subtitle: subtitle, movie: movie)
        #expect(target.lastPathComponent == "Film.sub")
    }

    @Test func changesPermissionsWhenConfigured() throws {
        let (movie, subtitle, dir) = try makeFiles()
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = try SubtitleMatcher(configuration: .init(changePermissionsTo: "600"))
            .match(subtitle: subtitle, movie: movie)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }
}

@Suite struct PostProcessorTests {
    private func makeSubtitle(_ content: String, encoding: String.Encoding = .utf8) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rqnapi-pp-\(UUID().uuidString).srt")
        try content.data(using: encoding, allowLossyConversion: false)!.write(to: url)
        return url
    }

    @Test func removesLinesContainingWords() throws {
        let subtitle = try makeSubtitle("keep me\nSPONSORED line\nalso keep")
        defer { try? FileManager.default.removeItem(at: subtitle) }

        SubtitlePostProcessor(
            settings: PostProcessingSettings(enabled: true, removeLinesWords: ["sponsored"])
        ).perform(subtitle: subtitle, frameRate: nil)

        let text = try String(contentsOf: subtitle, encoding: .utf8)
        #expect(text == "keep me\nalso keep")
    }

    @Test func convertsEncodingToUTF8() throws {
        let subtitle = try makeSubtitle("Zażółć gęślą jaźń", encoding: .windowsCP1250)
        defer { try? FileManager.default.removeItem(at: subtitle) }

        SubtitlePostProcessor(
            settings: PostProcessingSettings(
                enabled: true, encodingChangeMethod: .change, encodingTo: "UTF-8")
        ).perform(subtitle: subtitle, frameRate: nil)

        let text = try String(contentsOf: subtitle, encoding: .utf8)
        #expect(text == "Zażółć gęślą jaźń")
    }

    @Test func replacesDiacritics() throws {
        let subtitle = try makeSubtitle("Zażółć")
        defer { try? FileManager.default.removeItem(at: subtitle) }

        SubtitlePostProcessor(
            settings: PostProcessingSettings(
                enabled: true, encodingChangeMethod: .replaceDiacritics)
        ).perform(subtitle: subtitle, frameRate: nil)

        let text = try String(contentsOf: subtitle, encoding: .utf8)
        #expect(text == "Zazolc")
    }

    @Test func convertsFormatUsingFrameRate() throws {
        let subtitle = try makeSubtitle("1\n00:00:02,000 --> 00:00:04,000\nText\n")
        defer { try? FileManager.default.removeItem(at: subtitle) }

        SubtitlePostProcessor(
            settings: PostProcessingSettings(enabled: true, targetFormatName: "microdvd")
        ).perform(subtitle: subtitle, frameRate: 25)

        let text = try String(contentsOf: subtitle, encoding: .utf8)
        #expect(text.hasPrefix("{50}{100}Text"))
    }
}

@Suite struct DirectoryScannerTests {
    @Test func findsMoviesRecursivelyAndSkipsExistingSubtitles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rqnapi-scan-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("season1")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: root.appendingPathComponent("a.mkv"))
        try Data().write(to: nested.appendingPathComponent("b.avi"))
        try Data().write(to: nested.appendingPathComponent("b.srt"))
        try Data().write(to: nested.appendingPathComponent("notes.txt"))

        let all = DirectoryScanner().scan(
            directory: root, movieExtensions: ["mkv", "avi"])
        #expect(all.map(\.lastPathComponent).sorted() == ["a.mkv", "b.avi"])

        let withoutSubtitled = DirectoryScanner().scan(
            directory: root, movieExtensions: ["mkv", "avi"], skipIfSubtitlesExist: true)
        #expect(withoutSubtitled.map(\.lastPathComponent) == ["a.mkv"])
    }
}
