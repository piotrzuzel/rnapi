import Foundation
import RQNapiCore
import Security

/// Engine credentials live in the user's Keychain, never in defaults.
public protocol CredentialStore: Sendable {
    func credentials(forEngine engineID: String) -> EngineCredentials?
    func setCredentials(_ credentials: EngineCredentials?, forEngine engineID: String)
}

public struct KeychainCredentialStore: CredentialStore {
    private let servicePrefix: String

    public init(servicePrefix: String = "pl.xyn.rqnapi.engine") {
        self.servicePrefix = servicePrefix
    }

    private func service(for engineID: String) -> String {
        "\(servicePrefix).\(engineID)"
    }

    public func credentials(forEngine engineID: String) -> EngineCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: engineID),
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let existing = item as? [String: Any],
              let username = existing[kSecAttrAccount as String] as? String,
              let data = existing[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return EngineCredentials(username: username, password: password)
    }

    public func setCredentials(_ credentials: EngineCredentials?, forEngine engineID: String) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: engineID),
        ]
        SecItemDelete(baseQuery as CFDictionary)

        guard let credentials else { return }

        var attributes = baseQuery
        attributes[kSecAttrAccount as String] = credentials.username
        attributes[kSecValueData as String] = Data(credentials.password.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

/// In-memory store for tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: EngineCredentials] = [:]

    public init() {}

    public func credentials(forEngine engineID: String) -> EngineCredentials? {
        lock.withLock { storage[engineID] }
    }

    public func setCredentials(_ credentials: EngineCredentials?, forEngine engineID: String) {
        lock.withLock { storage[engineID] = credentials }
    }
}
