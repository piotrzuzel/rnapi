import Foundation

/// Match-quality classification, drives auto-selection and list highlighting
/// (legacy `SubtitleResolution`: GOOD > UNKNOWN > BAD).
public enum SubtitleResolution: Int, Sendable, Comparable, Hashable {
    case bad = 0
    case unknown = 1
    case good = 2

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A subtitle located by an engine's search, not yet placed next to the
/// movie. `handle` is engine-private (a temp file path or a remote file id).
public struct FoundSubtitle: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let engineID: String
    public let language: SubtitleLanguage
    public let title: String
    public let comment: String
    /// Hint for the subtitle file extension ("srt", "txt", ...).
    public let formatExtension: String
    public let resolution: SubtitleResolution
    /// Engine-private download handle; only meaningful to the engine that
    /// produced this result.
    public let handle: String

    public init(
        id: UUID = UUID(),
        engineID: String,
        language: SubtitleLanguage,
        title: String,
        comment: String = "",
        formatExtension: String,
        resolution: SubtitleResolution,
        handle: String
    ) {
        self.id = id
        self.engineID = engineID
        self.language = language
        self.title = title
        self.comment = comment
        self.formatExtension = formatExtension
        self.resolution = resolution
        self.handle = handle
    }
}
