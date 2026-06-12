/// How engines are consulted during search (legacy `SearchPolicy`).
public enum SearchPolicy: String, Sendable, Codable, CaseIterable {
    /// Stop at the first engine that returns results.
    case breakIfFound
    /// Query every engine, collect everything.
    case searchAll
    /// Query every engine in the primary *and* the backup language.
    case searchAllWithBackupLanguage
}

/// When the subtitle-selection list is shown (legacy `DownloadPolicy`).
public enum DownloadPolicy: String, Sendable, Codable, CaseIterable {
    case alwaysShowList
    case showListIfNeeded
    case neverShowList
}

/// What happens to the subtitle text encoding after download.
public enum EncodingChangeMethod: String, Sendable, Codable, CaseIterable {
    /// Keep the downloaded bytes untouched.
    case original
    /// Convert to `encodingTo` (optionally auto-detecting the source).
    case change
    /// Replace accented characters with ASCII look-alikes.
    case replaceDiacritics
}

/// Post-download processing options (legacy `PostProcessingConfig`).
public struct PostProcessingSettings: Sendable, Codable, Hashable {
    public var enabled: Bool
    public var encodingChangeMethod: EncodingChangeMethod
    /// When `false`, `encodingFrom` is trusted instead of detection.
    public var autoDetectEncoding: Bool
    /// IANA-style name, e.g. "windows-1250"; used when autodetect is off.
    public var encodingFrom: String
    public var encodingTo: String
    /// Target subtitle format name ("subrip", ...); nil = keep as-is.
    public var targetFormatName: String?
    /// Forced target file extension; nil = derive from format/source.
    public var targetExtension: String?
    /// Lines containing any of these words are removed (ad filtering).
    public var removeLinesWords: [String]
    /// Skip appending the "downloaded by QNapi" credit cue.
    public var skipCredit: Bool

    public init(
        enabled: Bool = false,
        encodingChangeMethod: EncodingChangeMethod = .original,
        autoDetectEncoding: Bool = true,
        encodingFrom: String = "windows-1250",
        encodingTo: String = "UTF-8",
        targetFormatName: String? = nil,
        targetExtension: String? = nil,
        removeLinesWords: [String] = [],
        skipCredit: Bool = true
    ) {
        self.enabled = enabled
        self.encodingChangeMethod = encodingChangeMethod
        self.autoDetectEncoding = autoDetectEncoding
        self.encodingFrom = encodingFrom
        self.encodingTo = encodingTo
        self.targetFormatName = targetFormatName
        self.targetExtension = targetExtension
        self.removeLinesWords = removeLinesWords
        self.skipCredit = skipCredit
    }
}
