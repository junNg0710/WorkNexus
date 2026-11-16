import CoreDomain
import Foundation

/// Ported from: lib/features/translation/data/repositories/credential_translation_api_config_repository.dart
/// Keeps the whole configuration — key included — as one credential-store item (`CredentialKey.translationApi`), so
/// reading it costs a single OS prompt rather than one per field.
public final class CredentialTranslationApiConfigRepository: TranslationApiConfigRepository, @unchecked Sendable {
    private let store: CredentialStore
    /// The last successful read: every translation asks for the configuration, and each ask would decode the JSON again.
    private let cached = Locked<TranslationApiConfig??>(nil)

    public init(store: CredentialStore) { self.store = store }

    public func load() async -> Outcome<TranslationApiConfig?> {
        if let hit = cached.withLock({ $0 }) { return .success(hit) }
        let config = await read()
        cached.withLock { $0 = .some(config) }
        return .success(config)
    }

    private func read() async -> TranslationApiConfig? {
        guard let raw = await store.read(CredentialKey.translationApi), !raw.isEmpty,
              let json = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else { return nil }
        return TranslationApiConfig(presetId: json["preset"] as? String ?? "custom", baseUrl: json["baseUrl"] as? String ?? "",
                                    model: json["model"] as? String ?? "", apiKey: json["apiKey"] as? String ?? "",
                                    enabled: json["enabled"] as? Bool ?? true)
    }

    public func save(_ config: TranslationApiConfig) async -> Outcome<Void> {
        let json: [String: Any] = ["preset": config.presetId, "baseUrl": config.baseUrl, "model": config.model,
                                   "apiKey": config.apiKey, "enabled": config.enabled]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return .failure(.storage("Could not save the translation key")) }
        switch await store.write(CredentialKey.translationApi, value: String(decoding: data, as: UTF8.self)) {
        case .success: cached.withLock { $0 = .some(config) }; return .success(())
        case .failure: return .failure(.storage("Could not save the translation key"))
        }
    }

    public func clear() async -> Outcome<Void> {
        switch await store.delete(CredentialKey.translationApi) {
        case .success: cached.withLock { $0 = .some(nil) }; return .success(())
        case .failure: return .failure(.storage("Could not remove the translation key"))
        }
    }
}
