/// Ported from: lib/tools/zentao/data/repositories/zentao_person_directory.dart (+ lib/app/di/zentao_people_module.dart)
import CoreDomain
import Foundation

/// `PersonDirectory` over ZenTao REST v1 `GET /users/{id}`. ZenTao user ids are the chat (xxd) user ids, so chat can ask by
/// its own id. Goes through each account's pooled client, so it shares the sync's session (ZenTao drops the previous
/// session on every sign-in).
public final class ZenTaoPersonDirectory: PersonDirectory, @unchecked Sendable {
    private let clients: ZenTaoClientProvider
    private let lock = NSLock()
    /// Departments per account, read once: they rarely change and every profile needs them.
    private var departments: [String: [JSON]] = [:]

    public init(clients: ZenTaoClientProvider) { self.clients = clients }

    public func lookup(accountId: String, userId: Int) async -> Outcome<PersonProfile> {
        guard let client = await clients.zenTaoClient(accountId: accountId) else { return .failure(.auth("No ZenTao connection credentials")) }
        do {
            let json = try await client.getV1Json("/users/\(userId)")
            return .success(mapZenTaoPerson(json, departments: await departmentsOf(accountId, client)))
        } catch let e as ZenTaoError {
            switch e {
            case .http(let status, _, _) where status == 401 || status == 403: return .failure(.auth("No access to ZenTao users"))
            case .http(let status, _, _) where status == 404: return .failure(.notFound("ZenTao user \(userId) not found"))
            case .format: return .failure(.parse("Invalid ZenTao user"))
            default: return .failure(.network("Could not load ZenTao user"))
            }
        } catch {
            return .failure(.unexpected("Could not load ZenTao user"))
        }
    }

    /// The account's departments, asked of the server once; none (no department path) when that fails.
    private func departmentsOf(_ accountId: String, _ client: ZenTaoClient) async -> [JSON] {
        if let cached = lock.withLock({ departments[accountId] }) { return cached }
        guard let list = try? await client.departments() else { return [] }
        lock.withLock { departments[accountId] = list }
        return list
    }
}

public extension ZentaoModuleData {
    /// Chat's colleague lookup (department, contacts, join date) over the sync's pooled ZenTao clients.
    static func personDirectory(sync: AccountSyncService, workspaces: WorkspaceRepository) -> PersonDirectory {
        ZenTaoPersonDirectory(clients: PooledZenTaoAdapters(sync: sync, accounts: WorkspaceZenTaoAccountLookup(workspaces)))
    }
}
