import Foundation

/// MicroDVD (.sub) — frame-based: `{start}{stop}text`.
public struct MicroDVDFormat: SubtitleFormat {
    public let name = "microdvd"
    public let isTimeBased = false
    public let defaultExtension = "sub"

    public init() {}

    nonisolated(unsafe) private static let line = /^\{(\d+)\}\{(\d+)\}(.*)$/

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
                    start: Int(match.1) ?? 0,
                    stop: Int(match.2) ?? 0,
                    tokens: TokenStream.decode(String(match.3))))
        }
        return script
    }

    public func encode(_ script: SubtitleScript) -> [String] {
        script.cues.map { cue in
            "{\(cue.start)}{\(cue.stop)}\(TokenStream.encodeBraceStyle(cue.tokens))"
        }
    }
}
