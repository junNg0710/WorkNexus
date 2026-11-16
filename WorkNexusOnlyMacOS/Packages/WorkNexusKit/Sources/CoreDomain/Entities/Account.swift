/// Ported from: lib/core/domain/entities/account.dart
public struct Account: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var workspaceId: String
    public var providerType: ProviderType
    public var handle: String
    public var baseUrl: String?
    public var credentialsRef: String?

    public init(id: String, workspaceId: String, providerType: ProviderType, handle: String,
                baseUrl: String? = nil, credentialsRef: String? = nil) {
        self.id = id; self.workspaceId = workspaceId; self.providerType = providerType
        self.handle = handle; self.baseUrl = baseUrl; self.credentialsRef = credentialsRef
    }

    private static func providerOrder(_ p: ProviderType) -> Int {
        switch p { case .zentao: 0; case .github: 1; case .gitlab: 2; case .jira: 3 }
    }

    /// ZenTao, GitHub, GitLab, then the rest; ties by id.
    public static func sort(_ accounts: [Account]) -> [Account] {
        accounts.sorted {
            let a = providerOrder($0.providerType), b = providerOrder($1.providerType)
            return a != b ? a < b : $0.id < $1.id
        }
    }
}
