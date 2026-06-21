/// A subtitle language known to RNapi, addressable by ISO 639-1 (two-letter),
/// engine-specific three-letter code, or English name.
///
/// The table is a verbatim port of the legacy `subtitlelanguage.cpp`; the
/// three-letter codes are *not* always ISO 639-2 (e.g. OpenSubtitles uses
/// "pob" for Brazilian Portuguese), so they must stay as-is.
public struct SubtitleLanguage: Sendable, Hashable {
    public let twoLetter: String
    public let threeLetter: String
    public let englishName: String

    init(_ twoLetter: String, _ threeLetter: String, _ englishName: String) {
        self.twoLetter = twoLetter
        self.threeLetter = threeLetter
        self.englishName = englishName
    }

    /// Resolves from a two-letter code, three-letter code or English name,
    /// mirroring legacy `SubtitleLanguage::setLanguage`.
    public init?(_ source: String) {
        let match: SubtitleLanguage?
        switch source.count {
        case 2:
            let lowered = source.lowercased()
            match = Self.all.first { $0.twoLetter == lowered }
        case 3:
            let lowered = source.lowercased()
            match = Self.all.first { $0.threeLetter == lowered }
        default:
            match = Self.all.first { $0.englishName == source }
        }
        guard let match else { return nil }
        self = match
    }

    public static let all: [SubtitleLanguage] = [
        SubtitleLanguage("sq", "alb", "Albanian"),
        SubtitleLanguage("en", "eng", "English"),
        SubtitleLanguage("ar", "ara", "Arabic"),
        SubtitleLanguage("bg", "bul", "Bulgarian"),
        SubtitleLanguage("zh", "chi", "Chinese"),
        SubtitleLanguage("hr", "hrv", "Croatian"),
        SubtitleLanguage("cs", "cze", "Czech"),
        SubtitleLanguage("da", "dan", "Danish"),
        SubtitleLanguage("et", "est", "Estonian"),
        SubtitleLanguage("fi", "fin", "Finnish"),
        SubtitleLanguage("fr", "fre", "French"),
        SubtitleLanguage("gl", "glg", "Galician"),
        SubtitleLanguage("el", "ell", "Greek"),
        SubtitleLanguage("he", "heb", "Hebrew"),
        SubtitleLanguage("es", "spa", "Spanish"),
        SubtitleLanguage("nl", "dut", "Dutch"),
        SubtitleLanguage("id", "ind", "Indonesian"),
        SubtitleLanguage("ja", "jpn", "Japanese"),
        SubtitleLanguage("ko", "kor", "Korean"),
        SubtitleLanguage("mk", "mac", "Macedonian"),
        SubtitleLanguage("de", "ger", "German"),
        SubtitleLanguage("no", "nor", "Norwegian"),
        SubtitleLanguage("oc", "oci", "Occitan"),
        SubtitleLanguage("fa", "per", "Persian (farsi)"),
        SubtitleLanguage("pl", "pol", "Polish"),
        SubtitleLanguage("pt", "por", "Portuguese"),
        SubtitleLanguage("pb", "pob", "Portuguese-BR"),
        SubtitleLanguage("ru", "rus", "Russian"),
        SubtitleLanguage("ro", "rum", "Romanian"),
        SubtitleLanguage("sr", "scc", "Serbian"),
        SubtitleLanguage("sl", "slv", "Slovenian"),
        SubtitleLanguage("sv", "swe", "Swedish"),
        SubtitleLanguage("sk", "slo", "Slovak"),
        SubtitleLanguage("tr", "tur", "Turkish"),
        SubtitleLanguage("vi", "vie", "Vietnamese"),
        SubtitleLanguage("hu", "hun", "Hungarian"),
        SubtitleLanguage("it", "ita", "Italian"),
    ]
}
