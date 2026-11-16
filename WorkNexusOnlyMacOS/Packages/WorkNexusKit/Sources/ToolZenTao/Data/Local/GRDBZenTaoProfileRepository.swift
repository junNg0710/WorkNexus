import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// The client a profile refresh talks through. The composition root passes the sync service's pooled client:
/// ZenTao invalidates the previous session on every login, so a client of this repository's own would knock the
/// sync's session out (and get knocked out in turn) on every startup.
public typealias ZenTaoProfileClientFactory = @Sendable (Account, String) -> ZenTaoClient

/// Ported from: lib/tools/zentao/data/repositories/local_zentao_profile_repository.dart
/// `ZenTaoProfileRepository` over the `zenTaoProfiles` table.
public final class GRDBZenTaoProfileRepository: ZenTaoProfileRepository, @unchecked Sendable {
    private let db: AppDatabase
    private let credentials: CredentialStore
    private let clientFactory: ZenTaoProfileClientFactory

    public init(db: AppDatabase, credentials: CredentialStore, clientFactory: ZenTaoProfileClientFactory? = nil) {
        self.db = db
        self.credentials = credentials
        self.clientFactory = clientFactory ?? { account, password in
            ZenTaoClient(baseUrl: account.baseUrl ?? "", account: account.handle, password: password)
        }
    }

    private static func storedJSON(_ row: ZenTaoProfileRow?) -> JSON? {
        guard let row, let any = try? jsonDecode(row.profileJson) else { return nil }
        return asMap(any)
    }

    public func watch(accountId: String) -> AsyncStream<ZenTaoProfile?> {
        db.observe { d in
            Self.storedJSON(try ZenTaoProfileRow.fetchOne(d, key: accountId)).flatMap { try? mapZenTaoProfile(accountId: accountId, $0) }
        }.removingDuplicates()
    }

    public func watchDepartments(accountId: String) -> AsyncStream<[ZenTaoDepartment]> {
        db.observe { d in
            guard let stored = Self.storedJSON(try ZenTaoProfileRow.fetchOne(d, key: accountId)),
                  let raw = stored["departments"] as? [Any] else { return [] }
            return mapZenTaoDepartments(raw.compactMap(asMap))
        }.removingDuplicates()
    }

    public func refresh(account: Account) async -> Outcome<ZenTaoProfile> {
        guard let ref = account.credentialsRef, let baseUrl = account.baseUrl, !baseUrl.isEmpty else {
            return .failure(.auth("No ZenTao connection credentials"))
        }
        guard let password = await credentials.read(ref), !password.isEmpty else { return .failure(.auth("ZenTao password is missing")) }
        do {
            let client = clientFactory(account, password)
            let json = try await client.userInfo()
            guard var profile = asMap(json["profile"]) else { return .failure(.parse("ZenTao response has no profile")) }
            if let avatar = profile["avatar"] as? String, !avatar.isEmpty,
               let resolved = URL(string: avatar, relativeTo: URL(string: "\(baseUrl)/"))?.absoluteURL {
                profile["avatar"] = resolved.absoluteString
            }
            let deptId = Int(str(profile["dept"]) ?? "") ?? 0
            var departments: [JSON] = []
            do {
                departments = try await client.departments()
                if deptId > 0 { profile["departmentPath"] = zenTaoDepartmentPath(deptId, departments) }
            } catch {
                // A failed department lookup only loses the department path.
            }
            let stored: JSON = ["profile": profile, "departments": departments]
            let mapped = try mapZenTaoProfile(accountId: account.id, stored, baseUrl: baseUrl)
            try await save(account.id, stored)
            return .success(mapped)
        } catch let e as ZenTaoError {
            switch e {
            case .http(let code, _, _) where code == 401 || code == 403: return .failure(.auth("ZenTao authentication failed"))
            case .format: return .failure(.parse("Invalid ZenTao profile"))
            default: return .failure(.network("Could not load ZenTao profile"))
            }
        } catch {
            return .failure(.unexpected("Could not save ZenTao profile"))
        }
    }

    public func update(account: Account, changes: ZenTaoProfileUpdate) async -> Outcome<ZenTaoProfile> {
        do {
            let row = try await db.writer.read { try ZenTaoProfileRow.fetchOne($0, key: account.id) }
            guard var stored = Self.storedJSON(row) else { return .failure(.notFound("Profile is not cached")) }
            var profile = asMap(stored["profile"]) ?? [:]
            guard let userId = Int(str(profile["id"]) ?? "") else { return .failure(.parse("ZenTao profile has no user ID")) }
            guard let client = await clientFor(account) else { return .failure(.auth("No ZenTao connection credentials")) }
            let oldRole = profile["role"]
            let oldRoleCode = asMap(oldRole).map { str($0["code"]) } ?? str(oldRole)
            var fields: JSON = [:]
            if str(profile["realname"]) != changes.realname { fields["realname"] = changes.realname }
            if (str(profile["email"]) ?? "") != changes.email { fields["email"] = changes.email }
            if (str(profile["mobile"]) ?? "") != changes.mobile { fields["mobile"] = changes.mobile }
            if (str(profile["phone"]) ?? "") != changes.phone { fields["phone"] = changes.phone }
            if let dept = changes.departmentId, Int(str(profile["dept"]) ?? "") != dept { fields["dept"] = dept }
            if let role = changes.roleCode, oldRoleCode != role { fields["role"] = role }
            if fields.isEmpty { return .success(try mapZenTaoProfile(accountId: account.id, stored)) }
            _ = try await client.updateUser(userId, fields: fields)
            for (k, v) in fields { profile[k] = v }
            if fields["role"] != nil { profile["role"] = ["code": changes.roleCode ?? "", "name": changes.roleCode ?? ""] as JSON }
            if fields["dept"] != nil, let raw = stored["departments"] as? [Any], let dept = changes.departmentId {
                profile["departmentPath"] = zenTaoDepartmentPath(dept, raw.compactMap(asMap))
            }
            stored["profile"] = profile
            try await save(account.id, stored)
            let refreshed = await refresh(account: account)
            if case .success = refreshed { return refreshed }
            return .success(try mapZenTaoProfile(accountId: account.id, stored))
        } catch let e as ZenTaoError {
            if case .http(let code, _, _) = e, code == 401 || code == 403 { return .failure(.auth("ZenTao authentication failed")) }
            return .failure(.network("Could not update ZenTao profile"))
        } catch {
            return .failure(.unexpected("Could not update ZenTao profile"))
        }
    }

    private func save(_ accountId: String, _ stored: JSON) async throws {
        let row = ZenTaoProfileRow(accountId: accountId, profileJson: jsonEncode(stored))
        try await db.writer.write { try row.save($0) }
    }

    private func clientFor(_ account: Account) async -> ZenTaoClient? {
        guard let ref = account.credentialsRef, let baseUrl = account.baseUrl, !baseUrl.isEmpty,
              let password = await credentials.read(ref), !password.isEmpty else { return nil }
        return clientFactory(account, password)
    }
}
