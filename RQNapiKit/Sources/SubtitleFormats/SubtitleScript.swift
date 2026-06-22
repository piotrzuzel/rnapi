/// Token of styled subtitle text — the common currency between formats.
public enum SubToken: Sendable, Hashable {
    case whitespace
    case word(String)
    case newline
    case bold
    case boldEnd
    case italic
    case italicEnd
    case underline
    case underlineEnd
    /// Payload is a hex RGB color without prefix (e.g. "ff0000").
    case fontColor(String)
    case fontColorEnd
}

/// One displayed subtitle. `start`/`stop` are milliseconds for time-based
/// formats and exact frame numbers for frame-based formats (matches the
/// legacy `SubEntry` convention; the converter translates between them).
public struct SubtitleCue: Sendable, Hashable {
    public var start: Int
    public var stop: Int
    public var tokens: [SubToken]

    public init(start: Int, stop: Int, tokens: [SubToken]) {
        self.start = start
        self.stop = stop
        self.tokens = tokens
    }

    /// Also matches the legacy "QNapi" credit so files processed by the old
    /// app don't get a second credit cue.
    public var containsRQNapiCredit: Bool {
        tokens.contains(.word("RQNapi")) || tokens.contains(.word("QNapi"))
    }
}

/// A parsed subtitle file.
public struct SubtitleScript: Sendable, Hashable {
    public var cues: [SubtitleCue]

    public init(cues: [SubtitleCue] = []) {
        self.cues = cues
    }
}
