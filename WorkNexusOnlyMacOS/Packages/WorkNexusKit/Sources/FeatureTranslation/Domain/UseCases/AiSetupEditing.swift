/// Not in the Flutter app: the edits the AI settings make to an `AiSetup`.
import Foundation

/// Pure edits of a setup; the caller saves the result. Each keeps the setup consistent: no choice points at a provider
/// that is gone, and provider ids stay unique.
public enum AiSetupEditing {
    /// A provider id that is readable in the stored JSON and not taken: `openai`, then `openai-2`, `openai-3`, …
    public static func newProviderId(presetId: String, existing: [String]) -> String {
        let base = presetId.isEmpty || presetId == AiModelChoice.openCodeId ? "provider" : presetId
        var id = base, n = 2
        while existing.contains(id) { id = "\(base)-\(n)"; n += 1 }
        return id
    }

    /// Adds `provider` under a fresh id (the one passed is ignored) and returns the setup with the id it got.
    public static func adding(_ provider: AiProvider, to setup: AiSetup) -> (setup: AiSetup, id: String) {
        var p = provider, s = setup
        p.id = newProviderId(presetId: provider.presetId, existing: setup.providers.map(\.id))
        s.providers.append(p)
        return (s, p.id)
    }

    /// Replaces the provider with the same id; an empty `apiKey` keeps the saved key (the edit form shows it masked).
    public static func updating(_ provider: AiProvider, in setup: AiSetup) -> AiSetup {
        var s = setup
        guard let i = s.providers.firstIndex(where: { $0.id == provider.id }) else { return s }
        var p = provider
        if p.apiKey.trimmingCharacters(in: .whitespaces).isEmpty { p.apiKey = s.providers[i].apiKey }
        s.providers[i] = p
        return s
    }

    /// Removes the provider; a choice that used it falls back to OpenCode with its default model. `fellBack` lists the
    /// purposes whose own choice changed, so the user can be told.
    public static func removing(_ providerId: String, from setup: AiSetup) -> (setup: AiSetup, fellBack: [AiPurpose]) {
        var s = setup, fellBack: [AiPurpose] = []
        s.providers.removeAll { $0.id == providerId }
        if s.translation.providerId == providerId { s.translation = .openCodeDefault; fellBack.append(.translation) }
        if s.chat?.providerId == providerId { s.chat = .openCodeDefault; fellBack.append(.chat) }
        return (s, fellBack)
    }

    /// Sets the choice of `purpose`. Picking another provider starts from its default model (empty).
    public static func choosing(_ choice: AiModelChoice, for purpose: AiPurpose, in setup: AiSetup) -> AiSetup {
        var s = setup
        switch purpose {
        case .translation: s.translation = choice
        case .chat: s.chat = choice
        }
        return s
    }

    /// "Same as translation" on drops chat's own choice; off starts it from what translation uses now, so nothing changes
    /// until the user picks something else.
    public static func chatSameAsTranslation(_ same: Bool, in setup: AiSetup) -> AiSetup {
        var s = setup
        s.chat = same ? nil : (setup.chat ?? setup.translation)
        return s
    }
}
