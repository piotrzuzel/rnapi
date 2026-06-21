/// A subtitle file format codec.
public protocol SubtitleFormat: Sendable {
    /// Stable identifier, matches legacy names: "subrip", "microdvd",
    /// "mpl2", "tmplayer".
    var name: String { get }
    /// Whether cue positions are timestamps (ms) or frame numbers.
    var isTimeBased: Bool { get }
    var defaultExtension: String { get }

    /// Cheap sniffing on the first lines of a file.
    func detect(lines: [String]) -> Bool
    func decode(lines: [String]) -> SubtitleScript
    func encode(_ script: SubtitleScript) -> [String]
}
