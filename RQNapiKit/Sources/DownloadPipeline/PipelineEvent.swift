import Foundation
import RQNapiCore

/// Why a single movie's subtitle download did not finish.
public enum PipelineFailure: Error, Sendable, Equatable {
    case hashingFailed
    case noSubtitlesFound
    case selectionCancelled
    case downloadFailed(String)
    case matchFailed(String)
}

/// Progress events emitted by the pipeline. The GUI renders them; the CLI
/// prints them — both consume the same stream.
public enum PipelineEvent: Sendable {
    case fileStarted(URL)
    case hashing(URL)
    case searching(URL, engineID: String, language: SubtitleLanguage)
    case resultsFound(URL, subtitles: [FoundSubtitle])
    case awaitingSelection(URL)
    case downloading(URL, subtitle: FoundSubtitle)
    case postProcessing(URL)
    case fileCompleted(URL, subtitle: URL)
    case fileFailed(URL, failure: PipelineFailure)
}

/// Per-batch outcome summary.
public struct PipelineSummary: Sendable {
    public var succeeded: [URL] = []
    public var failed: [(URL, PipelineFailure)] = []

    public init() {}
}
