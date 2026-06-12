import Foundation
import RNapiCore

/// Scan-directories options (legacy `ScanConfig`).
public struct ScanSettings: Sendable, Codable, Hashable {
    public var filters: [String]
    public var skipIfSubtitlesExist: Bool
    public var followSymlinks: Bool

    public init(
        filters: [String] = ScanSettings.defaultFilters,
        skipIfSubtitlesExist: Bool = false,
        followSymlinks: Bool = false
    ) {
        self.filters = filters
        self.skipIfSubtitlesExist = skipIfSubtitlesExist
        self.followSymlinks = followSymlinks
    }

    public static let defaultFilters = [
        "avi", "asf", "divx", "mkv", "mov", "mp4", "mpeg", "mpg", "ogm", "rm", "rmvb", "wmv",
    ]
}

/// The complete persisted configuration. Stored as one Codable blob in
/// UserDefaults so the CLI can read the GUI app's settings by suite name.
public struct AppConfiguration: Sendable, Codable, Hashable {
    public var languageCode: String
    public var backupLanguageCode: String?
    public var searchPolicy: SearchPolicy
    public var downloadPolicy: DownloadPolicy
    public var noBackup: Bool
    public var quietBatch: Bool
    public var engineOrder: [String]
    public var enabledEngines: Set<String>
    public var openSubtitlesApiKey: String?
    public var postProcessing: PostProcessingSettings
    public var changePermissionsTo: String?
    public var scan: ScanSettings
    public var showDockIcon: Bool

    public init(
        languageCode: String = "pl",
        backupLanguageCode: String? = "en",
        searchPolicy: SearchPolicy = .breakIfFound,
        downloadPolicy: DownloadPolicy = .showListIfNeeded,
        noBackup: Bool = false,
        quietBatch: Bool = false,
        engineOrder: [String] = ["NapiProjekt", "OpenSubtitles", "Napisy24"],
        enabledEngines: Set<String> = ["NapiProjekt", "OpenSubtitles", "Napisy24"],
        openSubtitlesApiKey: String? = nil,
        postProcessing: PostProcessingSettings = PostProcessingSettings(),
        changePermissionsTo: String? = nil,
        scan: ScanSettings = ScanSettings(),
        showDockIcon: Bool = true
    ) {
        self.languageCode = languageCode
        self.backupLanguageCode = backupLanguageCode
        self.searchPolicy = searchPolicy
        self.downloadPolicy = downloadPolicy
        self.noBackup = noBackup
        self.quietBatch = quietBatch
        self.engineOrder = engineOrder
        self.enabledEngines = enabledEngines
        self.openSubtitlesApiKey = openSubtitlesApiKey
        self.postProcessing = postProcessing
        self.changePermissionsTo = changePermissionsTo
        self.scan = scan
        self.showDockIcon = showDockIcon
    }
}

/// UserDefaults-backed persistence for `AppConfiguration`.
public struct SettingsStore: Sendable {
    /// Suite shared between the GUI app and the CLI.
    public static let suiteName = "pl.rnapi.RNapi"
    private static let key = "appConfiguration"

    private let suiteName: String

    public init(suiteName: String = SettingsStore.suiteName) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    public func load() -> AppConfiguration {
        guard let data = defaults?.data(forKey: Self.key),
              let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data)
        else {
            return AppConfiguration()
        }
        return configuration
    }

    public func save(_ configuration: AppConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}
