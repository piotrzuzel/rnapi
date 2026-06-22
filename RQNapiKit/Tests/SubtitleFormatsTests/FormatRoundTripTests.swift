import Testing

@testable import SubtitleFormats

@Suite struct FormatDetectionTests {
    private let srt = [
        "1",
        "00:00:01,000 --> 00:00:04,000",
        "Hello world",
        "",
        "2",
        "00:00:05,500 --> 00:00:07,250",
        "Second line",
        "with continuation",
        "",
    ]
    private let microdvd = ["{25}{100}Hello world", "{150}{200}{y:i}italics|second line"]
    private let mpl2 = ["[10][40]Hello world", "[55][72]/italic line"]
    private let tmplayer = ["00:00:01:Hello world", "00:00:06:Next|line"]

    @Test func detectsEachFormat() {
        #expect(SubtitleFormatsRegistry.detectFormat(lines: srt)?.name == "subrip")
        #expect(SubtitleFormatsRegistry.detectFormat(lines: microdvd)?.name == "microdvd")
        #expect(SubtitleFormatsRegistry.detectFormat(lines: mpl2)?.name == "mpl2")
        #expect(SubtitleFormatsRegistry.detectFormat(lines: tmplayer)?.name == "tmplayer")
        #expect(SubtitleFormatsRegistry.detectFormat(lines: ["random", "text"]) == nil)
    }

    @Test func srtDecodeTimesAndText() {
        let script = SubRipFormat().decode(lines: srt)
        #expect(script.cues.count == 2)
        #expect(script.cues[0].start == 1000)
        #expect(script.cues[0].stop == 4000)
        #expect(script.cues[1].start == 5500)
        #expect(script.cues[1].tokens.contains(.newline))
    }

    @Test func microdvdDecodeFrames() {
        let script = MicroDVDFormat().decode(lines: microdvd)
        #expect(script.cues[0].start == 25)
        #expect(script.cues[0].stop == 100)
        #expect(script.cues[1].tokens.first == .italic)
    }

    @Test func mpl2DecodeConvertsDecisecondsToMs() {
        let script = MPL2Format().decode(lines: mpl2)
        #expect(script.cues[0].start == 1000)
        #expect(script.cues[0].stop == 4000)
        #expect(script.cues[1].tokens.first == .italic)
    }

    @Test func tmplayerSynthesizesStopTimes() {
        let script = TMPlayerFormat().decode(lines: tmplayer)
        #expect(script.cues[0].start == 1000)
        // clipped to next cue start - 1 (6000 - 1) vs start + 5000 = 6000
        #expect(script.cues[0].stop == 5999)
        #expect(script.cues[1].stop == 11000)
    }
}

@Suite struct FormatRoundTripTests {
    private func roundTrip(_ format: any SubtitleFormat, _ lines: [String]) -> [String] {
        format.encode(format.decode(lines: lines))
    }

    @Test func srtRoundTripIsIdempotent() {
        let lines = [
            "1",
            "00:00:01,000 --> 00:00:04,000",
            "Hello <i>styled</i> world",
            "",
            "2",
            "01:02:03,456 --> 01:02:05,789",
            "Multi",
            "line",
            "",
        ]
        let once = roundTrip(SubRipFormat(), lines)
        let twice = roundTrip(SubRipFormat(), once)
        #expect(once == twice)
        #expect(once.contains("00:00:01,000 --> 00:00:04,000"))
        #expect(once.contains("01:02:03,456 --> 01:02:05,789"))
        #expect(once.contains("Hello <i>styled</i> world"))
    }

    @Test func microdvdRoundTripIsIdempotent() {
        let lines = ["{25}{100}Hello world", "{150}{200}{y:i}italics|second"]
        let once = roundTrip(MicroDVDFormat(), lines)
        let twice = roundTrip(MicroDVDFormat(), once)
        #expect(once == twice)
        #expect(once[0] == "{25}{100}Hello world")
        #expect(once[1] == "{150}{200}{y:i}italics|second")
    }

    @Test func mpl2RoundTripIsIdempotent() {
        let lines = ["[10][40]Hello world", "[55][72]plain"]
        let once = roundTrip(MPL2Format(), lines)
        #expect(once == lines)
    }

    @Test func tmplayerRoundTripPreservesStartTimes() {
        let lines = ["00:00:01: Hello world", "00:01:30: Next|line"]
        let once = roundTrip(TMPlayerFormat(), lines)
        #expect(once == lines)
    }
}

@Suite struct SubtitleConverterTests {
    @Test func convertsMicroDVDToSRTUsingFPS() throws {
        let lines = ["{50}{100}Frame based"]
        let output = try SubtitleConverter().convert(
            lines: lines, to: "subrip", frameRate: { 25.0 })
        // frame 50 @ 25fps = 2000 ms, frame 100 = 4000 ms
        #expect(output.contains("00:00:02,000 --> 00:00:04,000"))
    }

    @Test func convertsSRTToMicroDVD() throws {
        let lines = ["1", "00:00:02,000 --> 00:00:04,000", "Time based", ""]
        let output = try SubtitleConverter().convert(
            lines: lines, to: "microdvd", frameRate: { 25.0 })
        #expect(output == ["{50}{100}Time based"])
    }

    @Test func timeToTimeConversionNeedsNoFPS() throws {
        let lines = ["1", "00:00:01,000 --> 00:00:02,000", "Text", ""]
        let output = try SubtitleConverter().convert(
            lines: lines, to: "mpl2", frameRate: { nil })
        #expect(output == ["[10][20]Text"])
    }

    @Test func missingFPSThrowsWhenRequired() {
        let lines = ["{50}{100}Frame based"]
        #expect(throws: SubtitleConversionError.self) {
            try SubtitleConverter().convert(lines: lines, to: "subrip", frameRate: { nil })
        }
    }

    @Test func appliesDelayOffset() throws {
        let lines = ["1", "00:00:01,000 --> 00:00:02,000", "Text", ""]
        let output = try SubtitleConverter().convert(
            lines: lines, to: "subrip", frameRate: { nil }, delaySeconds: 1.5)
        #expect(output.contains("00:00:02,500 --> 00:00:03,500"))
    }

    @Test func appendsCreditCue() throws {
        let lines = ["1", "00:00:01,000 --> 00:00:02,000", "Text", ""]
        let output = try SubtitleConverter().convert(
            lines: lines, to: "subrip", frameRate: { nil },
            credit: SubtitleCredit(text: "Downloaded by RQNapi", url: "http://rqnapi.github.io"))
        #expect(output.contains("00:00:04,000 --> 00:00:12,000"))
        #expect(output.contains(where: { $0.contains("rqnapi.github.io") }))
    }

    @Test func unknownFormatThrows() {
        #expect(throws: SubtitleConversionError.self) {
            try SubtitleConverter().convert(
                lines: ["garbage"], to: "subrip", frameRate: { nil })
        }
    }
}

@Suite struct TokenStreamTests {
    @Test func decodesStyledText() {
        let tokens = TokenStream.decode("<b>Bold</b> and <i>italic</i>")
        #expect(tokens.first == .bold)
        #expect(tokens.contains(.word("Bold")))
        #expect(tokens.contains(.boldEnd))
        #expect(tokens.contains(.italic))
    }

    @Test func decodesColorTags() {
        #expect(
            TokenStream.decode("{c:$ff0000}red{/c}")
                == [.fontColor("ff0000"), .word("red"), .fontColorEnd])
        #expect(
            TokenStream.decode("<font color=\"#00ff00\">green</font>")
                == [.fontColor("00ff00"), .word("green"), .fontColorEnd])
    }

    @Test func leadingSlashMeansItalic() {
        let tokens = TokenStream.decode("/italic text")
        #expect(tokens.first == .italic)
    }

    @Test func collapsesWhitespaceRuns() {
        #expect(TokenStream.decode("a   b") == [.word("a"), .whitespace, .word("b")])
    }
}
