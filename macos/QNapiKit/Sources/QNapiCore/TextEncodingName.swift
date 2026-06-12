import Foundation

/// Mapping between user-facing encoding names (settings, CLI flags) and
/// `String.Encoding`. Covers the encodings the legacy app offered.
public enum TextEncodingName {
    public static let supported: [String] = [
        "UTF-8", "windows-1250", "ISO-8859-2", "windows-1257", "ISO-8859-13", "ISO-8859-16",
    ]

    public static func encoding(named name: String) -> String.Encoding? {
        switch name.lowercased() {
        case "utf-8", "utf8": .utf8
        case "windows-1250", "cp1250": .windowsCP1250
        case "iso-8859-2", "latin2": .isoLatin2
        case "windows-1257", "cp1257": .windowsCP1257
        case "iso-8859-13": .isoLatin13
        case "iso-8859-16": .isoLatin16
        default: nil
        }
    }
}
