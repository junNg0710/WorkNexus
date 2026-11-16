import CoreDomain
import Foundation
import Security

/// Ported from: lib/core/platform/credential_store.dart. One keychain item (`worknexus.vault`) holds a JSON map,
/// so the user sees a single keychain prompt. Uses the legacy login keychain (no data-protection keychain), like the Flutter build.
public actor KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account = "worknexus.vault"
    private var cache: [String: String]?

    public init(service: String = "com.worknexus.macos") { self.service = service }

    public func read(_ key: String) async -> String? { loadVault()[key] }

    public func write(_ key: String, value: String) async -> Outcome<Void> {
        var v = loadVault(); v[key] = value; return store(v)
    }
    public func delete(_ key: String) async -> Outcome<Void> {
        var v = loadVault(); v[key] = nil; return store(v)
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func loadVault() -> [String: String] {
        if let cache { return cache }
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let vault: [String: String]
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
           let m = try? JSONDecoder().decode([String: String].self, from: data) { vault = m } else { vault = [:] }
        cache = vault
        return vault
    }

    private func store(_ vault: [String: String]) -> Outcome<Void> {
        guard let data = try? JSONEncoder().encode(vault) else { return .failure(.storage("encode vault")) }
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return .failure(.storage("keychain error \(status)")) }
        cache = vault
        return .success(())
    }
}

/// Test double.
public actor InMemoryCredentialStore: CredentialStore {
    private var values: [String: String] = [:]
    public init() {}
    public func read(_ key: String) async -> String? { values[key] }
    public func write(_ key: String, value: String) async -> Outcome<Void> { values[key] = value; return .success(()) }
    public func delete(_ key: String) async -> Outcome<Void> { values[key] = nil; return .success(()) }
}
