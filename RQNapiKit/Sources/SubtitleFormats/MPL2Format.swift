import Foundation

/// MPL2 (.txt) — time-based in deciseconds: `[start][stop]text`.
/// Cue positions are stored in milliseconds (×100 on decode, ÷100 on encode).
public struct MPL2Format: SubtitleFormat {
    public let name = "mpl2"
    public let isTimeBased = true
    public let defaultExtension = "txt"

    public init() {}

    nonisolated(unsafe) private static let line = /^\[(\d+)\]\[(\d+)\](.*)$/

    public func detect(lines: [String]) -> Bool {
        guard let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return false }
        return first.wholeMatch(of: Self.line) != nil
    }

    public func decode(lines: [String]) -> SubtitleScript {
        var script = SubtitleScript()
        for text in lines {
            guard let match = text.wholeMatch(of: Self.line) else { continue }
            script.cues.append(
                SubtitleCue(
                    start: 100 * (Int(match.1) ?? 0),
                    stop: 100 * (Int(match.2) ?? 0),
                    tokens: TokenStream.decode(String(match.3))))
        }
        return script
    }

    public func encode(_ script: SubtitleScript) -> [String] {
        script.cues.map { cue in
            "[\(cue.start / 100)][\(cue.stop / 100)]\(TokenStream.encodeBraceStyle(cue.tokens))"
        }
    }
}
