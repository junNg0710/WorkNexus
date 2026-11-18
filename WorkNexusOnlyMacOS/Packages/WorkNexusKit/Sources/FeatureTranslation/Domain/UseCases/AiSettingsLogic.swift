/// Not in the Flutter app: what the AI provider settings and the "Translate with …" labels show, apart from drawing it.
import Foundation

public enum AiSettingsLogic {
    /// The name the UI gives a backend: the provider's name, with the model when it is short enough to read at a glance
    /// (`OpenAI (gpt-5-mini)`, `OpenCode (gpt-5-nano)`); a `provider/model` id shows only its model part.
    public static func displayName(_ backend: AiBackend, openCodeName: String = "OpenCode", maxModelLength: Int = 20) -> String {
        let (name, model): (String, String?) = switch backend {
        case .openCode(let m): (openCodeName, m)
        case .api(let provider, let config): (provider.name, config.model)
        }
        let short = model.map { m in m.split(separator: "/").last.map(String.init) ?? m } ?? ""
        return short.isEmpty || short.count > maxModelLength ? name : "\(name) (\(short))"
    }

    /// What `purpose` runs on, named for a label.
    public static func backendName(_ setup: AiSetup, purpose: AiPurpose, legacyModel: String?, openCodeName: String = "OpenCode") -> String {
        displayName(ResolveAiBackend()(setup, purpose: purpose, callerModel: legacyModel), openCodeName: openCodeName)
    }

    /// The host of an endpoint (`api.openai.com`), shown under a saved provider; nil when the URL has none.
    public static func host(of baseUrl: String) -> String? {
        let t = baseUrl.trimmingCharacters(in: .whitespaces)
        guard let host = URL(string: t.contains("://") ? t : "https://\(t)")?.host, !host.isEmpty else { return nil }
        return host
    }

    /// Recognizable but not recoverable: the last four characters behind a fixed mask; nil for no key.
    public static func maskedKey(_ key: String) -> String? {
        let k = key.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return nil }
        return "••••••" + (k.count > 8 ? String(k.suffix(4)) : "")
    }

    /// The add / edit form can be saved: a name, an endpoint, and a key when the preset needs one (an edit may leave the
    /// key empty to keep the saved one).
    public static func canSaveProvider(preset: TranslationApiPreset, name: String, baseUrl: String, apiKey: String,
                                       hasSavedKey: Bool, saving: Bool) -> Bool {
        !saving && !name.trimmed.isEmpty && !baseUrl.trimmed.isEmpty
            && (!preset.needsKey || !apiKey.trimmed.isEmpty || hasSavedKey)
    }

    /// The provider the form describes. A preset keeps its own name and endpoint; only a custom one takes what was typed
    /// (falling back to the endpoint's host for a name).
    public static func provider(id: String, preset: TranslationApiPreset, name: String, baseUrl: String, apiKey: String) -> AiProvider {
        let isCustom = preset.id == TranslationApiPreset.custom.id
        let url = isCustom ? baseUrl.trimmed : (baseUrl.trimmed.isEmpty ? preset.baseUrl : baseUrl.trimmed)
        let typed = name.trimmed
        let label = isCustom ? (typed.isEmpty ? host(of: url) ?? preset.name : typed) : (typed.isEmpty ? preset.name : typed)
        return AiProvider(id: id, presetId: preset.id, name: label, baseUrl: url, apiKey: apiKey.trimmed)
    }

    /// The providers a purpose can pick from, by id: OpenCode first, then the saved ones in order.
    public static func choiceIds(_ setup: AiSetup) -> [String] { [AiModelChoice.openCodeId] + setup.providers.map(\.id) }

    /// The choice after picking `providerId` in a purpose's provider dropdown: the same provider keeps its model, another
    /// starts from its default.
    public static func pick(providerId: String, current: AiModelChoice) -> AiModelChoice {
        providerId == current.providerId ? current : AiModelChoice(providerId: providerId, model: "")
    }

    /// The model the OpenCode picker of `purpose` shows: its own, else (where translation's choice is in force) the legacy
    /// pin in `AppSettings.translationModel`.
    public static func openCodeModel(_ setup: AiSetup, purpose: AiPurpose, legacyModel: String) -> String {
        if case .openCode(let m) = ResolveAiBackend()(setup, purpose: purpose, callerModel: legacyModel) { return m ?? "" }
        return setup.choice(for: purpose).model
    }

    /// The `provider/model` whose OpenCode key the settings offer to manage: translation's when it runs on OpenCode, else AI
    /// in chat's, else the legacy pin.
    public static func openCodeKeyModel(_ setup: AiSetup, legacyModel: String) -> String {
        for purpose in AiPurpose.allCases {
            if case .openCode(let m) = ResolveAiBackend()(setup, purpose: purpose, callerModel: legacyModel) { return m ?? "" }
        }
        return legacyModel
    }
}

private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
