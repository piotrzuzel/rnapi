import Foundation

/// TMPlayer (.txt) — time-based with second resolution: `HH:MM:SS:text`.
/// Stop times are synthesized: start + 5 s, clipped to the next cue.
public struct TMPlayerFormat: SubtitleFormat {
    public let name = "tmplayer"
    public let isTimeBased = true
    public let defaultExtension = "txt"

    public init() {}

    nonisolated(unsafe) private static let line = /^(\d{2}):(\d{2}):(\d{2}):(.*)$/

    public func detect(lines: [String]) -> Bool {
        guard let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return false }
        return first.wholeMatch(of: Self.line) != nil
    }

    public func decode(lines: [String]) -> SubtitleScript {
        var script = SubtitleScript()
        for text in lines {
            guard let match = text.wholeMatch(of: Self.line) else { continue }
            let h = Int(match.1) ?? 0
            let m = Int(match.2) ?? 0
            let s = Int(match.3) ?? 0
            let start = 1000 * (3600 * h + 60 * m + s)
            script.cues.append(
                SubtitleCue(start: start, stop: 0, tokens: TokenStream.decode(String(match.4))))
        }

        for index in script.cues.indices {
            let plus5s = script.cues[index].start + 5000
            if index < script.cues.count - 1 {
                script.cues[index].stop = min(plus5s, script.cues[index + 1].start - 1)
            } else {
                script.cues[index].stop = plus5s
            }
        }
        return script
    }

    public func encode(_ script: SubtitleScript) -> [String] {
        script.cues.map { cue in
            let totalSeconds = cue.start / 1000
            let h = totalSeconds / 3600
            let m = (totalSeconds % 3600) / 60
            let s = totalSeconds % 60
            return String(format: "%02d:%02d:%02d: ", h, m, s)
                + TokenStream.encodeBraceStyle(cue.tokens)
        }
    }
}
