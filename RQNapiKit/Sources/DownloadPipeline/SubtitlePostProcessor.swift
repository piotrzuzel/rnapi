import Foundation
import RQNapiCore
import SubtitleFormats

/// In-place post-processing of a matched subtitle file: ad-line removal,
/// encoding conversion, format conversion. Port of legacy
/// `subtitlepostprocessor.cpp` (same operation order).
public struct SubtitlePostProcessor: Sendable {
    public static let credit = SubtitleCredit(
        text: "Subtitles downloaded and processed by RQNapi",
        url: "http://rqnapi.github.io")

    private let settings: PostProcessingSettings

    public init(settings: PostProcessingSettings) {
        self.settings = settings
    }

    /// `frameRate` is consulted only when format conversion needs it.
    public func perform(subtitle: URL, frameRate: Double?) {
        guard settings.enabled else { return }

        if !settings.removeLinesWords.isEmpty {
            removeLinesContainingWords(in: subtitle)
        }

        switch settings.encodingChangeMethod {
        case .original:
            break
        case .replaceDiacritics:
            replaceDiacritics(in: subtitle)
        case .change:
            changeEncoding(of: subtitle)
        }

        if let targetFormat = settings.targetFormatName {
            convertFormat(of: subtitle, to: targetFormat, frameRate: frameRate)
        }
    }

    // MARK: - Steps

    private func removeLinesContainingWords(in subtitle: URL) {
        rewriteText(of: subtitle) { text in
            text.components(separatedBy: "\n")
                .filter { line in
                    !settings.removeLinesWords.contains { word in
                        line.range(of: word, options: .caseInsensitive) != nil
                    }
                }
                .joined(separator: "\n")
        }
    }

    private func replaceDiacritics(in subtitle: URL) {
        rewriteText(of: subtitle, transform: TextEncodingDetector.replaceDiacriticsWithASCII)
    }

    private func changeEncoding(of subtitle: URL) {
        guard let data = try? Data(contentsOf: subtitle),
              let targetEncoding = TextEncodingName.encoding(named: settings.encodingTo)
        else { return }

        let text: String?
        if settings.autoDetectEncoding {
            text = TextEncodingDetector.decode(data)
        } else {
            let from = TextEncodingName.encoding(named: settings.encodingFrom) ?? .utf8
            text = String(data: data, encoding: from)
        }

        guard let text, let converted = text.data(using: targetEncoding, allowLossyConversion: true)
        else { return }
        try? converted.write(to: subtitle)
    }

    private func convertFormat(of subtitle: URL, to formatName: String, frameRate: Double?) {
        guard let data = try? Data(contentsOf: subtitle) else { return }
        let encoding = TextEncodingDetector.detectEncoding(of: data)
        guard let text = String(data: data, encoding: encoding) else { return }

        let lines = text.components(separatedBy: .newlines)
        guard
            let converted = try? SubtitleConverter().convert(
                lines: lines,
                to: formatName,
                frameRate: { frameRate },
                credit: settings.skipCredit ? nil : Self.credit)
        else { return }

        let output = converted.joined(separator: "\n") + "\n"
        // Written back in the same encoding the file already had.
        try? output.data(using: encoding, allowLossyConversion: true)?.write(to: subtitle)
    }

    private func rewriteText(of subtitle: URL, transform: (String) -> String) {
        guard let data = try? Data(contentsOf: subtitle) else { return }
        let encoding = TextEncodingDetector.detectEncoding(of: data)
        guard let text = String(data: data, encoding: encoding) else { return }
        let output = transform(text)
        try? output.data(using: encoding, allowLossyConversion: true)?.write(to: subtitle)
    }
}
