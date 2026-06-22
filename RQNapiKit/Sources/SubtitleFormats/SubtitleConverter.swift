import Foundation

public enum SubtitleConversionError: Error, Sendable {
    case unknownSourceFormat
    case frameRateUnavailable
}

/// Optional credit cue appended after the last subtitle (legacy behavior,
/// disabled with the "skip convert ads" setting).
public struct SubtitleCredit: Sendable {
    public let text: String
    public let url: String

    public init(text: String, url: String) {
        self.text = text
        self.url = url
    }
}

/// Converts parsed subtitles between formats, translating frame/timestamp
/// units using the movie frame rate when source and target disagree.
/// Port of legacy `SubtitleConverter::convertSubtitles`.
public struct SubtitleConverter: Sendable {
    public init() {}

    /// - Parameters:
    ///   - frameRate: resolved lazily — only consulted when the conversion
    ///     actually needs it (frame-based ↔ time-based, or frame delay).
    ///   - fpsRatio: scales all positions (e.g. 25/23.976 retiming).
    ///   - delaySeconds: shifts all cues, clamped at zero.
    public func convert(
        lines: [String],
        to targetFormatName: String,
        frameRate: () -> Double?,
        fpsRatio: Double = 1.0,
        delaySeconds: Double = 0.0,
        credit: SubtitleCredit? = nil
    ) throws -> [String] {
        guard let sourceFormat = SubtitleFormatsRegistry.detectFormat(lines: lines),
              let targetFormat = SubtitleFormatsRegistry.format(named: targetFormatName)
        else {
            throw SubtitleConversionError.unknownSourceFormat
        }

        var script = sourceFormat.decode(lines: lines)
        var resolvedRate: Double?

        func requireFrameRate() throws -> Double {
            if let resolvedRate { return resolvedRate }
            guard let rate = frameRate(), rate > 0 else {
                throw SubtitleConversionError.frameRateUnavailable
            }
            resolvedRate = rate
            return rate
        }

        if sourceFormat.isTimeBased != targetFormat.isTimeBased {
            let rate = try requireFrameRate()
            for index in script.cues.indices {
                if targetFormat.isTimeBased {
                    script.cues[index].start = Self.frameToMs(script.cues[index].start, rate)
                    script.cues[index].stop = Self.frameToMs(script.cues[index].stop, rate)
                } else {
                    script.cues[index].start = Self.msToFrame(script.cues[index].start, rate)
                    script.cues[index].stop = Self.msToFrame(script.cues[index].stop, rate)
                }
            }
        }

        if fpsRatio != 1.0 {
            for index in script.cues.indices {
                script.cues[index].start = Int((fpsRatio * Double(script.cues[index].start)).rounded(.down))
                script.cues[index].stop = Int((fpsRatio * Double(script.cues[index].stop)).rounded(.down))
            }
        }

        if delaySeconds != 0.0 {
            let offset = Int(delaySeconds * 1000.0)
            if targetFormat.isTimeBased {
                for index in script.cues.indices {
                    script.cues[index].start = max(0, script.cues[index].start + offset)
                    script.cues[index].stop = max(0, script.cues[index].stop + offset)
                }
            } else {
                let rate = try requireFrameRate()
                for index in script.cues.indices {
                    script.cues[index].start = max(
                        0, Self.msToFrame(Self.frameToMs(script.cues[index].start, rate) + offset, rate))
                    script.cues[index].stop = max(
                        0, Self.msToFrame(Self.frameToMs(script.cues[index].stop, rate) + offset, rate))
                }
            }
        }

        if let credit, let last = script.cues.last, !last.containsRQNapiCredit {
            let creditCue: SubtitleCue
            var tokens = TokenStream.decode(credit.text + "|")
            tokens.append(.word(credit.url))
            if targetFormat.isTimeBased {
                let start = last.stop + 2000
                creditCue = SubtitleCue(start: start, stop: start + 8000, tokens: tokens)
            } else {
                let start = last.stop + 50
                creditCue = SubtitleCue(start: start, stop: start + 200, tokens: tokens)
            }
            script.cues.append(creditCue)
        }

        return targetFormat.encode(script)
    }

    public func detectFormat(lines: [String]) -> (any SubtitleFormat)? {
        SubtitleFormatsRegistry.detectFormat(lines: lines)
    }

    private static func msToFrame(_ ms: Int, _ rate: Double) -> Int {
        Int((rate * Double(ms) / 1000.0).rounded(.down))
    }

    private static func frameToMs(_ frame: Int, _ rate: Double) -> Int {
        Int((1000.0 * Double(frame) / rate).rounded(.down))
    }
}
