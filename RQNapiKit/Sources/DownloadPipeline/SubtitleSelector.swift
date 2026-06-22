import Foundation
import RQNapiCore

/// Decides which of several found subtitles to download when the download
/// policy calls for user input. The GUI implementation suspends until the
/// user picks from a list; the CLI prompts on stdin or auto-picks.
public protocol SubtitleSelector: Sendable {
    /// Return nil to skip this movie.
    func choose(from subtitles: [FoundSubtitle], movie: URL) async -> FoundSubtitle?
}

/// Picks the best match without asking: first GOOD result, else the first.
public struct BestMatchSelector: SubtitleSelector {
    public init() {}

    public func choose(from subtitles: [FoundSubtitle], movie: URL) async -> FoundSubtitle? {
        bestMatch(in: subtitles)
    }
}

/// Shared auto-pick rule (legacy `bestIdx`).
public func bestMatch(in subtitles: [FoundSubtitle]) -> FoundSubtitle? {
    subtitles.first(where: { $0.resolution == .good }) ?? subtitles.first
}
