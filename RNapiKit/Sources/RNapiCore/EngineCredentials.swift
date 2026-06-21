/// User credentials for subtitle services that accept them.
public struct EngineCredentials: Sendable, Hashable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}
