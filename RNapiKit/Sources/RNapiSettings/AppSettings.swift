import Foundation
import Observation
import RNapiCore

/// Observable wrapper around the persisted configuration — the GUI's single
/// settings hub. Every mutation persists immediately.
@MainActor
@Observable
public final class AppSettings {
    public private(set) var configuration: AppConfiguration
    public let credentialStore: any CredentialStore

    private let store: SettingsStore

    public init(
        store: SettingsStore = SettingsStore(),
        credentialStore: any CredentialStore = KeychainCredentialStore()
    ) {
        self.store = store
        self.credentialStore = credentialStore
        self.configuration = store.load()
    }

    public func update(_ mutate: (inout AppConfiguration) -> Void) {
        var updated = configuration
        mutate(&updated)
        configuration = updated
        store.save(updated)
    }
}
