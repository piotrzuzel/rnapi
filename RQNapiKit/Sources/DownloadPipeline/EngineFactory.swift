import Engines
import Foundation
import RQNapiCore

/// Builds engine instances from settings — shared by GUI app and CLI.
public enum EngineFactory {
    public static let allEngineIDs = ["OpenSubtitles", "NapiProjekt", "Napisy24"]
    public static let defaultOrder = ["NapiProjekt", "OpenSubtitles", "Napisy24"]

    /// - Parameters:
    ///   - order: engine IDs in user-configured priority order.
    ///   - enabled: subset of `order` that is active.
    ///   - credentials: per-engine user credentials (Keychain-backed).
    ///   - openSubtitlesApiKey: enables the OpenSubtitles REST API; when
    ///     nil/empty, the legacy anonymous XML-RPC API is used instead.
    public static func makeEngines(
        order: [String],
        enabled: Set<String>,
        credentials: (String) -> EngineCredentials?,
        openSubtitlesApiKey: String?,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> [any SubtitleEngine] {
        order.filter(enabled.contains).compactMap { id -> (any SubtitleEngine)? in
            switch id {
            case "NapiProjekt":
                return NapiProjektEngine(
                    credentials: credentials(id), temporaryDirectory: temporaryDirectory)
            case "Napisy24":
                return Napisy24Engine(
                    credentials: credentials(id), temporaryDirectory: temporaryDirectory)
            case "OpenSubtitles":
                guard let apiKey = openSubtitlesApiKey, !apiKey.isEmpty else {
                    return OpenSubtitlesXmlRpcEngine(credentials: credentials(id))
                }
                return OpenSubtitlesEngine(
                    configuration: OpenSubtitlesConfiguration(
                        apiKey: apiKey, credentials: credentials(id)))
            default:
                return nil
            }
        }
    }

    public static func metadata(for id: String) -> EngineMetadata? {
        switch id {
        case "NapiProjekt": NapiProjektEngine().metadata
        case "Napisy24": Napisy24Engine().metadata
        case "OpenSubtitles":
            OpenSubtitlesEngine(configuration: OpenSubtitlesConfiguration(apiKey: "")).metadata
        default: nil
        }
    }
}
