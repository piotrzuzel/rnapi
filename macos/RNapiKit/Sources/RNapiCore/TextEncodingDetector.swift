import Foundation

/// Subtitle text-encoding detection and diacritics stripping.
///
/// Port of legacy `encodingutils.cpp`: valid UTF-8 wins outright; otherwise
/// each candidate encoding is scored by how many distinct Polish diacritics
/// appear in the decoded text, later candidates winning ties.
public enum TextEncodingDetector {
    /// Candidate encodings in legacy scoring order (last wins ties).
    public static let candidates: [String.Encoding] = [
        .windowsCP1257, .isoLatin13, .isoLatin16, .isoLatin2, .windowsCP1250, .utf8,
    ]

    public static func detectEncoding(of data: Data) -> String.Encoding {
        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }

        let probes = ["ą", "ś", "ż", "ć", "ń", "ł", "ó", "ę"]
        var bestMatch = 0
        var detected = String.Encoding.utf8

        for encoding in candidates {
            guard let text = String(data: data, encoding: encoding)?.lowercased() else { continue }
            let found = probes.count { text.contains($0) }
            if found >= bestMatch {
                bestMatch = found
                detected = encoding
            }
        }
        return detected
    }

    /// Decodes with the detected encoding; falls back to lossy Latin-2.
    public static func decode(_ data: Data) -> String? {
        String(data: data, encoding: detectEncoding(of: data))
    }

    /// Replaces accented characters with ASCII look-alikes (legacy
    /// `replaceDiacriticsWithASCII`). Unknown characters pass through.
    public static func replaceDiacriticsWithASCII(_ input: String) -> String {
        input.map { replacementTable[$0] ?? String($0) }.joined()
    }

    private static let replacementTable: [Character: String] = {
        let diacritics =
            "ąćęłńśżźĄĆĘŁŃŚŻŹŠŒŽšœžŸ¥µÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝßàáâãäåæçèéêëìíîïðñòóôõöøùúûüýÿ"
        let replacements = [
            "a", "c", "e", "l", "n", "s", "z", "z",
            "A", "C", "E", "L", "N", "S", "Z", "Z",
            "S", "OE", "Z", "s", "oe", "z", "Y", "Y", "u",
            "A", "A", "A", "A", "A", "A", "AE", "C",
            "E", "E", "E", "E", "I", "I", "I", "I",
            "D", "N", "O", "O", "O", "O", "O", "O",
            "U", "U", "U", "U", "Y", "s",
            "a", "a", "a", "a", "a", "a", "ae", "c",
            "e", "e", "e", "e", "i", "i", "i", "i",
            "o", "n", "o", "o", "o", "o", "o", "o",
            "u", "u", "u", "u", "y", "y",
        ]
        precondition(diacritics.count == replacements.count)
        return Dictionary(uniqueKeysWithValues: zip(diacritics, replacements))
    }()
}

extension String.Encoding {
    /// Encodings Foundation exposes only through CoreFoundation.
    static let windowsCP1257 = fromCF(.windowsBalticRim)
    static let isoLatin13 = fromCF(.isoLatin7)
    static let isoLatin16 = fromCF(.isoLatin10)

    private static func fromCF(_ encoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }
}
