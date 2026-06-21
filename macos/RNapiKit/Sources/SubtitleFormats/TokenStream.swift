import Foundation

/// Shared tokenizer for inline subtitle markup, port of legacy
/// `SubtitleFormat::decodeTokenStream`. Understands MicroDVD (`{y:b}`,
/// `{c:$RRGGBB}`, `|`), MPL2 (`/` italics) and HTML-ish SRT tags.
enum TokenStream {
    private static let namedTokens: [(String, SubToken)] = [
        ("{y:b}", .bold), ("{b}", .bold), ("<b>", .bold),
        ("{y:i}", .italic), ("{i}", .italic), ("<i>", .italic),
        ("{y:u}", .underline), ("{u}", .underline), ("<u>", .underline),
        ("{/y:b}", .boldEnd), ("{/b}", .boldEnd), ("</b>", .boldEnd),
        ("{/y:i}", .italicEnd), ("{/i}", .italicEnd), ("</i>", .italicEnd),
        ("{/y:u}", .underlineEnd), ("{/u}", .underlineEnd), ("</u>", .underlineEnd),
        ("{/c}", .fontColorEnd), ("</font>", .fontColorEnd),
        ("|", .newline), ("\r\n", .newline), ("\n", .newline),
    ]

    nonisolated(unsafe) private static let braceColor = /^\{c:(.*?)\}/.ignoresCase()
    nonisolated(unsafe) private static let fontColor = /^<font color=(.*?)>/.ignoresCase()

    static func decode(_ input: String) -> [SubToken] {
        var stream = Substring(input)
        var tokens: [SubToken] = []
        var wordBuffer = ""

        func flushWord() {
            if !wordBuffer.isEmpty {
                tokens.append(.word(wordBuffer))
                wordBuffer = ""
            }
        }

        outer: while let first = stream.first {
            for (text, token) in namedTokens {
                if let range = stream.range(
                    of: text, options: [.caseInsensitive, .anchored])
                {
                    stream = stream[range.upperBound...]
                    flushWord()
                    tokens.append(token)
                    continue outer
                }
            }

            if let match = try? braceColor.firstMatch(in: stream) {
                stream = stream[match.range.upperBound...]
                flushWord()
                tokens.append(.fontColor(parseColor(String(match.1))))
            } else if let match = try? fontColor.firstMatch(in: stream) {
                stream = stream[match.range.upperBound...]
                flushWord()
                tokens.append(.fontColor(parseColor(String(match.1))))
            } else if first == "/", wordBuffer.isEmpty {
                stream = stream.dropFirst()
                flushWord()
                tokens.append(.italic)
            } else if first.isWhitespace {
                stream = stream.drop(while: \.isWhitespace)
                flushWord()
                tokens.append(.whitespace)
            } else {
                wordBuffer.append(first)
                stream = stream.dropFirst()
            }
        }

        flushWord()

        while tokens.first == .whitespace {
            tokens.removeFirst()
        }
        return tokens
    }

    private static func parseColor(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "$", with: "")
    }

    /// Token serialization shared by the frame-based formats (MicroDVD,
    /// MPL2, TMPlayer): `|` newlines and `{y:x}` style tags.
    static func encodeBraceStyle(_ tokens: [SubToken]) -> String {
        tokens.map { token in
            switch token {
            case .whitespace: " "
            case .word(let text): text
            case .newline: "|"
            case .bold: "{y:b}"
            case .italic: "{y:i}"
            case .underline: "{y:u}"
            case .fontColor(let color): "{c:$\(color)}"
            case .boldEnd, .italicEnd, .underlineEnd, .fontColorEnd: ""
            }
        }.joined()
    }
}
