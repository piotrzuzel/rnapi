/// Known formats in legacy registration order — detection tries them
/// in sequence, so the order is part of the behavior.
public enum SubtitleFormatsRegistry {
    public static let all: [any SubtitleFormat] = [
        SubRipFormat(), MicroDVDFormat(), MPL2Format(), TMPlayerFormat(),
    ]

    public static func format(named name: String) -> (any SubtitleFormat)? {
        all.first { $0.name == name }
    }

    public static func detectFormat(lines: [String]) -> (any SubtitleFormat)? {
        all.first { $0.detect(lines: lines) }
    }
}
