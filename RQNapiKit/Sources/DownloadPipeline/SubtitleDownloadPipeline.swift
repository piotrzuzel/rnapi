import Engines
import Foundation
import MediaInfo
import RQNapiCore

public struct PipelineConfiguration: Sendable {
    public var language: SubtitleLanguage
    public var backupLanguage: SubtitleLanguage?
    public var searchPolicy: SearchPolicy
    public var downloadPolicy: DownloadPolicy
    public var postProcessing: PostProcessingSettings
    public var changePermissionsTo: String?
    public var temporaryDirectory: URL
    public var maxConcurrentFiles: Int

    public init(
        language: SubtitleLanguage,
        backupLanguage: SubtitleLanguage? = nil,
        searchPolicy: SearchPolicy = .searchAll,
        downloadPolicy: DownloadPolicy = .showListIfNeeded,
        postProcessing: PostProcessingSettings = PostProcessingSettings(),
        changePermissionsTo: String? = nil,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        maxConcurrentFiles: Int = 3
    ) {
        self.language = language
        self.backupLanguage = backupLanguage
        self.searchPolicy = searchPolicy
        self.downloadPolicy = downloadPolicy
        self.postProcessing = postProcessing
        self.changePermissionsTo = changePermissionsTo
        self.temporaryDirectory = temporaryDirectory
        self.maxConcurrentFiles = maxConcurrentFiles
    }
}

/// The per-file subtitle flow: hash → search engines (per policy) → select →
/// download/unpack → place next to movie → post-process. Port of the legacy
/// legacy `QNapi` C++ orchestrator + the CLI/GUI driver loops around it.
public struct SubtitleDownloadPipeline: Sendable {
    private let engines: [any SubtitleEngine]
    private let selector: any SubtitleSelector
    private let movieInfoProvider: any MovieInfoProvider
    private let configuration: PipelineConfiguration

    public init(
        engines: [any SubtitleEngine],
        selector: any SubtitleSelector = BestMatchSelector(),
        movieInfoProvider: any MovieInfoProvider = AVFoundationMovieInfoProvider(),
        configuration: PipelineConfiguration
    ) {
        self.engines = engines
        self.selector = selector
        self.movieInfoProvider = movieInfoProvider
        self.configuration = configuration
    }

    /// Processes a batch with bounded concurrency; events for all files are
    /// interleaved on one stream and the stream finishes when all are done.
    public func run(movies: [URL]) -> AsyncStream<PipelineEvent> {
        let pipeline = self
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    var pending = movies.makeIterator()
                    var active = 0

                    func enqueueNext() {
                        guard let movie = pending.next() else { return }
                        active += 1
                        group.addTask {
                            await pipeline.process(movie: movie) { event in
                                continuation.yield(event)
                            }
                        }
                    }

                    for _ in 0..<max(1, pipeline.configuration.maxConcurrentFiles) {
                        enqueueNext()
                    }
                    while active > 0 {
                        await group.next()
                        active -= 1
                        enqueueNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs one movie through the pipeline, emitting progress events.
    public func process(movie: URL, emit: @Sendable (PipelineEvent) -> Void) async {
        emit(.fileStarted(movie))

        emit(.hashing(movie))
        let descriptor: MovieFileDescriptor
        do {
            descriptor = try MovieFileDescriptor.hashing(url: movie)
        } catch {
            print("[SubtitleDownloadPipeline] hashing failed for \(movie.path): \(error)")
            emit(.fileFailed(movie, failure: .hashingFailed))
            return
        }

        let results = await search(descriptor: descriptor, movie: movie, emit: emit)
        guard !results.isEmpty else {
            emit(.fileFailed(movie, failure: .noSubtitlesFound))
            return
        }
        emit(.resultsFound(movie, subtitles: results))

        guard let chosen = await choose(from: results, movie: movie, emit: emit) else {
            emit(.fileFailed(movie, failure: .selectionCancelled))
            return
        }

        emit(.downloading(movie, subtitle: chosen))
        let workDirectory = configuration.temporaryDirectory
            .appendingPathComponent("rqnapi-\(UUID().uuidString)")
        defer {
            do {
                if FileManager.default.fileExists(atPath: workDirectory.path) {
                    try FileManager.default.removeItem(at: workDirectory)
                }
            } catch {
                print("[SubtitleDownloadPipeline] failed to remove work directory \(workDirectory.path): \(error)")
            }
        }

        let downloaded: URL
        do {
            guard let engine = engines.first(where: { $0.metadata.id == chosen.engineID }) else {
                emit(.fileFailed(movie, failure: .downloadFailed("unknown engine")))
                return
            }
            downloaded = try await engine.download(chosen, to: workDirectory)
        } catch {
            emit(.fileFailed(movie, failure: .downloadFailed(String(describing: error))))
            return
        }

        let matcher = SubtitleMatcher(
            configuration: SubtitleMatcher.Configuration(
                postProcessingEnabled: configuration.postProcessing.enabled,
                targetFormatName: configuration.postProcessing.targetFormatName,
                targetExtension: configuration.postProcessing.targetExtension,
                changePermissionsTo: configuration.changePermissionsTo))

        let target: URL
        do {
            target = try matcher.match(subtitle: downloaded, movie: movie)
        } catch {
            emit(.fileFailed(movie, failure: .matchFailed(String(describing: error))))
            return
        }

        if configuration.postProcessing.enabled {
            emit(.postProcessing(movie))
            var frameRate: Double?
            if configuration.postProcessing.targetFormatName != nil {
                frameRate = await movieInfoProvider.movieInfo(for: movie)?.frameRate
            }
            SubtitlePostProcessor(settings: configuration.postProcessing)
                .perform(subtitle: target, frameRate: frameRate)
        }

        emit(.fileCompleted(movie, subtitle: target))
    }

    // MARK: - Search

    private func search(
        descriptor: MovieFileDescriptor, movie: URL, emit: @Sendable (PipelineEvent) -> Void
    ) async -> [FoundSubtitle] {
        var results: [FoundSubtitle] = []
        let primary = configuration.language
        let backup = configuration.backupLanguage

        func searchEngines(language: SubtitleLanguage, breakIfFound: Bool) async {
            for engine in engines {
                emit(.searching(movie, engineID: engine.metadata.id, language: language))
                do {
                    let found = try await engine.search(file: descriptor, language: language)
                    results.append(contentsOf: found)
                } catch {
                    print("[SubtitleDownloadPipeline] search failed engine=\(engine.metadata.id) language=\(language): \(error)")
                }
                if breakIfFound && !results.isEmpty { return }
            }
        }

        switch configuration.searchPolicy {
        case .searchAllWithBackupLanguage:
            await searchEngines(language: primary, breakIfFound: false)
            if let backup, backup != primary {
                await searchEngines(language: backup, breakIfFound: false)
            }
        case .searchAll, .breakIfFound:
            let breakEarly = configuration.searchPolicy == .breakIfFound
            await searchEngines(language: primary, breakIfFound: breakEarly)
            if results.isEmpty, let backup, backup != primary {
                await searchEngines(language: backup, breakIfFound: breakEarly)
            }
        }

        // Stable order: primary language first, then backup, then others
        // (legacy `listSubtitles` ranking).
        func rank(_ subtitle: FoundSubtitle) -> Int {
            if subtitle.language == primary { return 0 }
            if subtitle.language == backup { return 1 }
            return 2
        }
        return results.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private func choose(
        from results: [FoundSubtitle], movie: URL, emit: @Sendable (PipelineEvent) -> Void
    ) async -> FoundSubtitle? {
        let needList: Bool
        switch configuration.downloadPolicy {
        case .alwaysShowList:
            needList = true
        case .neverShowList:
            needList = false
        case .showListIfNeeded:
            // Ask only when there are several candidates and none is a
            // confirmed hash match (legacy `needToShowList`).
            needList = results.count > 1 && !results.contains { $0.resolution == .good }
        }

        if needList {
            emit(.awaitingSelection(movie))
            return await selector.choose(from: results, movie: movie)
        }
        return bestMatch(in: results)
    }
}
