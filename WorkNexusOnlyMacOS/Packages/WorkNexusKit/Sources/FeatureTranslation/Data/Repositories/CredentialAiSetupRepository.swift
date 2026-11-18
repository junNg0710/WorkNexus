/// Not in the Flutter app: every saved AI provider and the choice per purpose, as one credential-store item.
import CoreDomain
import Foundation

/// Keeps the whole `AiSetup` — keys included — as one credential-store item (`CredentialKey.aiSetup`), so reading it costs
/// a single OS prompt and adding a provider never loses another's key. Cached after the first read: every AI run asks.
///
/// Migration: when the item is missing and an earlier build's single config (`CredentialKey.translationApi`) exists, the
/// setup is built from it (`MigrateTranslationApiConfig`) and saved; the old item is deleted once the new one is written,
/// so a key the user later removes here does not linger in the old item.
public final class CredentialAiSetupRepository: AiSetupRepository, @unchecked Sendable {
    private let store: CredentialStore
    private let legacy: TranslationApiConfigRepository
    private let cached = Locked<AiSetup?>(nil)

    public init(store: CredentialStore, legacy: TranslationApiConfigRepository? = nil) {
        self.store = store
        self.legacy = legacy ?? CredentialTranslationApiConfigRepository(store: store)
    }

    public func load() async -> Outcome<AiSetup> {
        if let hit = cached.withLock({ $0 }) { return .success(hit) }
        if let raw = await store.read(CredentialKey.aiSetup), !raw.isEmpty {
            guard let dto = try? JSONDecoder().decode(AiSetupDTO.self, from: Data(raw.utf8)) else {
                return .failure(.storage("Could not read the saved AI providers"))
            }
            let setup = dto.setup
            cached.withLock { $0 = setup }
            return .success(setup)
        }
        let setup = await migrated()
        cached.withLock { $0 = setup }
        return .success(setup)
    }

    /// The setup an earlier build's config becomes (saved, the old item then removed); `.empty` when there is none.
    private func migrated() async -> AiSetup {
        guard case .success(let old?) = await legacy.load() else { return .empty }
        let setup = MigrateTranslationApiConfig()(old)
        if case .success = await write(setup) { _ = await legacy.clear() }
        return setup
    }

    public func save(_ setup: AiSetup) async -> Outcome<Void> {
        switch await write(setup) {
        case .success: cached.withLock { $0 = setup }; return .success(())
        case .failure(let f): return .failure(f)
        }
    }

    private func write(_ setup: AiSetup) async -> Outcome<Void> {
        guard let data = try? JSONEncoder().encode(AiSetupDTO(setup)) else { return .failure(.storage("Could not save the AI providers")) }
        switch await store.write(CredentialKey.aiSetup, value: String(decoding: data, as: UTF8.self)) {
        case .success: return .success(())
        case .failure: return .failure(.storage("Could not save the AI providers"))
        }
    }
}
