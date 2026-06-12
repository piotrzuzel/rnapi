import Foundation

/// SubRip (.srt) — time-based: `HH:MM:SS,mmm --> HH:MM:SS,mmm`.
public struct SubRipFormat: SubtitleFormat {
    public let name = "subrip"
    public let isTimeBased = true
    public let defaultExtension = "srt"

    public init() {}

    nonisolated(unsafe) private static let inlineTimestamps =
        /^(\d+)\s+(\d{2}):(\d{2}):(\d{2}),(\d{3})\s+-->\s+(\d{2}):(\d{2}):(\d{2}),(\d{3})(.*)$/
    nonisolated(unsafe) private static let timestamps =
        /^(\d{2}):(\d{2}):(\d{2}),(\d{3})\s+-->\s+(\d{2}):(\d{2}):(\d{2}),(\d{3})(.*)$/
    nonisolated(unsafe) private static let numericLine = /^\d+$/
    nonisolated(unsafe) private static let detectPattern =
        /^(\d+)(\n|\r\n|\s+)(\d{2}):(\d{2}):(\d{2}),(\d{3})\s+-->\s+(\d{2}):(\d{2}):(\d{2}),(\d{3})(.*)$/
        .dotMatchesNewlines()

    public func detect(lines: [String]) -> Bool {
        var lines = lines
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }

        var firstEntry = ""
        for line in lines {
            if line.isEmpty { break }
            firstEntry += line + "\n"
        }

        return firstEntry.wholeMatch(of: Self.detectPattern) != nil
    }

    public func decode(lines: [String]) -> SubtitleScript {
        var script = SubtitleScript()
        var tokensBuffer = ""
        var numsBuffer = ""
        var start = 0
        var stop = 0

        func flushEntry() {
            guard !tokensBuffer.isEmpty else { return }
            var tokens = TokenStream.decode(tokensBuffer)
            while tokens.last == .newline {
                tokens.removeLast()
            }
            script.cues.append(SubtitleCue(start: start, stop: stop, tokens: tokens))
            tokensBuffer = ""
        }

        for line in lines {
            if let match = line.wholeMatch(of: Self.inlineTimestamps) {
                flushEntry()
                start = Self.milliseconds(match.2, match.3, match.4, match.5)
                stop = Self.milliseconds(match.6, match.7, match.8, match.9)
                numsBuffer = ""
            } else if let match = line.wholeMatch(of: Self.timestamps) {
                flushEntry()
                start = Self.milliseconds(match.1, match.2, match.3, match.4)
                stop = Self.milliseconds(match.5, match.6, match.7, match.8)
                numsBuffer = ""
            } else if line.wholeMatch(of: Self.numericLine) != nil {
                // Either a cue index (dropped when timestamps follow) or
                // genuinely numeric subtitle text (kept otherwise).
                numsBuffer += line + "\n"
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !numsBuffer.isEmpty {
                    tokensBuffer += numsBuffer
                    numsBuffer = ""
                }
                tokensBuffer += line + "\n"
            }
        }
        flushEntry()

        return script
    }

    public func encode(_ script: SubtitleScript) -> [String] {
        var lines: [String] = []
        for (index, cue) in script.cues.enumerated() {
            lines.append(String(index + 1))
            lines.append(
                "\(Self.timestamp(cue.start)) --> \(Self.timestamp(cue.stop))")
            lines.append(contentsOf: Self.encodeTokens(cue.tokens).components(separatedBy: "\n"))
            lines.append("")
        }
        return lines
    }

    private static func milliseconds(
        _ h: Substring, _ m: Substring, _ s: Substring, _ ms: Substring
    ) -> Int {
        3_600_000 * Int(h)! + 60000 * Int(m)! + 1000 * Int(s)! + Int(ms)!
    }

    private static func timestamp(_ ms: Int) -> String {
        let h = ms / 3_600_000
        let m = (ms % 3_600_000) / 60000
        let s = (ms % 60000) / 1000
        let rest = ms % 1000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, rest)
    }

    private static func encodeTokens(_ tokens: [SubToken]) -> String {
        tokens.map { token in
            switch token {
            case .whitespace: " "
            case .word(let text): text
            case .newline: "\n"
            case .bold: "<b>"
            case .boldEnd: "</b>"
            case .italic: "<i>"
            case .italicEnd: "</i>"
            case .underline: "<u>"
            case .underlineEnd: "</u>"
            case .fontColor(let color): "<font color=\"#\(color)\">"
            case .fontColorEnd: "</font>"
            }
        }.joined()
    }
}
