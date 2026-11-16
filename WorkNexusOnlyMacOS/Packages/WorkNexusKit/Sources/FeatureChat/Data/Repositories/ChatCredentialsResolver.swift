import CoreDomain
import Foundation

/// Finds what chat needs to sign in: the xxd address (stored, else derived from the ZenTao base URL), the saved ZenTao
/// password and the account name.
/// Ported from: lib/features/chat/data/repositories/chat_credentials_resolver.dart
struct ChatCredentialsResolver: Sendable {
    let local: ChatLocalDatasource
    let store: CredentialStore

    func resolve(_ accountId: String) async -> Outcome<XxdCredentials> {
        do {
            guard let account = try await local.account(accountId), account.providerType == .zentao else { return .failure(.notFound("Not a ZenTao account")) }
            let chat = try await local.chatAccount(accountId)
            guard let server = chat?.serverUrl.flatMap(URL.init(string:)) ?? Self.xxdServer(for: account.baseUrl) else {
                return .failure(.notFound("No chat server address"))
            }
            let password: String? = await {
                if let ref = account.credentialsRef { return await store.read(ref) }
                return await store.read(CredentialKey.accountSecret(accountId))
            }()
            guard let password, !password.isEmpty else { return .failure(.auth("No saved ZenTao password")) }
            // The REST login matches the account case-insensitively, xxd does not: a handle typed as `abc` for account `Abc`
            // syncs fine but chat refuses it. Sign in with the name ZenTao itself reports (stored profile), else the handle.
            let name = try await local.zenTaoAccountName(accountId) ?? account.handle
            return .success(XxdCredentials(server: server, account: name, password: password, pinnedFingerprint: chat?.pinnedFingerprint))
        } catch { return .failure(.storage("Could not read chat credentials: \(error.localizedDescription)")) }
    }

    /// `https://<zentao host>:11443`
    static func xxdServer(for zentaoBaseUrl: String?) -> URL? {
        guard let base = zentaoBaseUrl.flatMap({ URL(string: $0) }), let host = base.host, !host.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "https"; c.host = host; c.port = 11443
        return c.url
    }
}
