import Foundation
import Security

/// New (no Dart counterpart): one generic-password item of a keychain service, without its secret.
struct KeychainEntry: Equatable, Sendable {
    /// What tells the item from the others of its service.
    var account: String
    /// The name Keychain Access shows.
    var label: String
}

struct KeychainItemError: Error, Equatable { let status: Int32 }

/// The generic-password items of one keychain service. Behind a protocol so nothing but the app itself ever touches the real
/// keychain: tests (and the demo build) use `InMemoryKeychainItemStore`.
protocol KeychainItemStore: Sendable {
    /// Every item, attributes only: the secrets are not read (so macOS never asks for this).
    func entries() throws -> [KeychainEntry]
    /// The secret of `account`; nil when there is no such item.
    func data(account: String) throws -> Data?
    /// Adds the item, or replaces the secret (and label) of the one already there.
    func set(account: String, label: String, data: Data) throws
    func remove(account: String) throws
    func removeAll() throws
}

/// The login keychain (`kSecClassGenericPassword`), like `CorePersistence.KeychainCredentialStore`.
struct SystemKeychainItemStore: KeychainItemStore {
    let service: String

    private func query(_ account: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    func entries() throws -> [KeychainEntry] {
        var q = query()
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let rows = out as? [[String: Any]] else { throw KeychainItemError(status: status) }
        return rows.compactMap { row in
            guard let account = row[kSecAttrAccount as String] as? String else { return nil }
            return KeychainEntry(account: account, label: row[kSecAttrLabel as String] as? String ?? "")
        }
    }

    func data(account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainItemError(status: status) }
        return data
    }

    func set(account: String, label: String, data: Data) throws {
        let changes: [String: Any] = [kSecValueData as String: data, kSecAttrLabel as String: label]
        var status = SecItemUpdate(query(account) as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(account).merging(changes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainItemError(status: status) }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainItemError(status: status) }
    }

    func removeAll() throws {
        for entry in try entries() { try remove(account: entry.account) }
    }
}

/// The same items kept in memory: the tests' double and the demo build's store. Nothing leaves the process.
final class InMemoryKeychainItemStore: KeychainItemStore, @unchecked Sendable {
    private let items = Locked<[String: (label: String, data: Data)]>([:])
    /// How often a secret was read, so a test can tell a list from a read.
    private let reads = Locked<Int>(0)

    var secretReads: Int { reads.withLock { $0 } }

    func entries() throws -> [KeychainEntry] {
        items.withLock { all in all.map { KeychainEntry(account: $0.key, label: $0.value.label) }.sorted { $0.account < $1.account } }
    }

    func data(account: String) throws -> Data? {
        reads.withLock { $0 += 1 }
        return items.withLock { $0[account]?.data }
    }

    func set(account: String, label: String, data: Data) throws { items.withLock { $0[account] = (label, data) } }
    func remove(account: String) throws { items.withLock { $0[account] = nil } }
    func removeAll() throws { items.withLock { $0 = [:] } }
}

/// Where the mini apps keep their secrets (saved sign-ins, session cookies): the system keychain, or memory only.
public struct MiniAppsSecretStorage: Sendable {
    let logins: KeychainItemStore
    let sessionCookies: KeychainItemStore

    /// The login keychain, under services of their own.
    public static var keychain: MiniAppsSecretStorage {
        MiniAppsSecretStorage(logins: SystemKeychainItemStore(service: "com.worknexus.macos.weblogins"),
                              sessionCookies: SystemKeychainItemStore(service: "com.worknexus.macos.websession"))
    }

    /// Kept for this run only: tests and the demo build, which must never touch the user's keychain.
    public static func inMemory() -> MiniAppsSecretStorage {
        MiniAppsSecretStorage(logins: InMemoryKeychainItemStore(), sessionCookies: InMemoryKeychainItemStore())
    }
}
