import DownloadPipeline
import Foundation
import Observation
import RQNapiCore
import RQNapiSettings

/// A subtitle list waiting for the user's pick; resuming the continuation
/// unblocks the pipeline mid-flow.
public struct PendingSelection: Identifiable {
    public let id = UUID()
    public let movie: URL
    public let subtitles: [FoundSubtitle]
    let continuation: CheckedContinuation<FoundSubtitle?, Never>

    public func resolve(_ subtitle: FoundSubtitle?) {
        continuation.resume(returning: subtitle)
    }
}

/// The GUI's stateful hub: owns the download queue, drives the pipeline and
/// translates its events into observable per-item state.
@MainActor
@Observable
public final class DownloadSession {
    public enum ItemState: Equatable {
        case queued
        case hashing
        case searching(engine: String)
        case awaitingSelection
        case downloading
        case postProcessing
        case completed(subtitle: URL)
        case failed(message: String)

        public var isFinished: Bool {
            switch self {
            case .completed, .failed: true
            default: false
            }
        }
    }

    public struct QueueItem: Identifiable, Equatable {
        public let id: UUID
        public let movie: URL
        public var state: ItemState
    }

    public private(set) var items: [QueueItem] = []
    public var pendingSelection: PendingSelection?
    public private(set) var isRunning = false
    /// Quiet batch ("Open with" launch): auto-pick best, quit when done.
    public var batchMode = false
    public var onBatchFinished: (@MainActor () -> Void)?

    private let settings: AppSettings
    private var pendingMovies: [URL] = []

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var scanSettings: ScanSettings {
        settings.configuration.scan
    }

    public var summary: (succeeded: Int, failed: Int) {
        items.reduce(into: (0, 0)) { counts, item in
            switch item.state {
            case .completed: counts.0 += 1
            case .failed: counts.1 += 1
            default: break
            }
        }
    }

    public func enqueue(_ movies: [URL]) {
        let new = movies.filter { movie in
            !items.contains { $0.movie == movie && !$0.state.isFinished }
        }
        guard !new.isEmpty else { return }
        items.append(contentsOf: new.map { QueueItem(id: UUID(), movie: $0, state: .queued) })

        if isRunning {
            pendingMovies.append(contentsOf: new)
        } else {
            startBatch(new)
        }
    }

    public func clearFinished() {
        items.removeAll(where: \.state.isFinished)
    }

    // MARK: - Pipeline plumbing

    private func startBatch(_ movies: [URL]) {
        isRunning = true
        let pipeline = makePipeline()
        Task {
            for await event in pipeline.run(movies: movies) {
                apply(event)
            }
            if pendingMovies.isEmpty {
                isRunning = false
                if batchMode {
                    onBatchFinished?()
                }
            } else {
                let next = pendingMovies
                pendingMovies = []
                startBatch(next)
            }
        }
    }

    private func makePipeline() -> SubtitleDownloadPipeline {
        let configuration = settings.configuration
        let credentialStore = settings.credentialStore
        let engines = EngineFactory.makeEngines(
            order: configuration.engineOrder,
            enabled: configuration.enabledEngines,
            credentials: { credentialStore.credentials(forEngine: $0) },
            openSubtitlesApiKey: configuration.openSubtitlesApiKey)

        let downloadPolicy = batchMode ? .neverShowList : configuration.downloadPolicy

        return SubtitleDownloadPipeline(
            engines: engines,
            selector: SessionSelector(session: self),
            configuration: PipelineConfiguration(
                language: SubtitleLanguage(configuration.languageCode) ?? SubtitleLanguage("pl")!,
                backupLanguage: configuration.backupLanguageCode.flatMap(SubtitleLanguage.init),
                searchPolicy: configuration.searchPolicy,
                downloadPolicy: downloadPolicy,
                noBackup: configuration.noBackup,
                postProcessing: configuration.postProcessing,
                changePermissionsTo: configuration.changePermissionsTo))
    }

    private func apply(_ event: PipelineEvent) {
        switch event {
        case .fileStarted(let movie):
            setState(.queued, for: movie)
        case .hashing(let movie):
            setState(.hashing, for: movie)
        case .searching(let movie, let engineID, _):
            setState(.searching(engine: engineID), for: movie)
        case .resultsFound:
            break
        case .awaitingSelection(let movie):
            setState(.awaitingSelection, for: movie)
        case .downloading(let movie, _):
            setState(.downloading, for: movie)
        case .postProcessing(let movie):
            setState(.postProcessing, for: movie)
        case .fileCompleted(let movie, let subtitle):
            setState(.completed(subtitle: subtitle), for: movie)
        case .fileFailed(let movie, let failure):
            setState(.failed(message: Self.describe(failure)), for: movie)
        }
    }

    private func setState(_ state: ItemState, for movie: URL) {
        guard let index = items.lastIndex(where: { $0.movie == movie }) else { return }
        items[index].state = state
    }

    func requestSelection(movie: URL, subtitles: [FoundSubtitle]) async -> FoundSubtitle? {
        await withCheckedContinuation { continuation in
            pendingSelection = PendingSelection(
                movie: movie, subtitles: subtitles, continuation: continuation)
        }
    }

    static func describe(_ failure: PipelineFailure) -> String {
        switch failure {
        case .hashingFailed: String(localized: "Could not read the movie file")
        case .noSubtitlesFound: String(localized: "No subtitles found")
        case .selectionCancelled: String(localized: "Cancelled")
        case .downloadFailed: String(localized: "Download failed")
        case .matchFailed: String(localized: "Could not write the subtitle file")
        }
    }
}

/// Bridges the pipeline's selection callback onto the main actor and
/// suspends until the user picks from the sheet.
private struct SessionSelector: SubtitleSelector {
    let session: DownloadSession

    func choose(from subtitles: [FoundSubtitle], movie: URL) async -> FoundSubtitle? {
        await session.requestSelection(movie: movie, subtitles: subtitles)
    }
}
