/// Not in the Flutter app: turns the one API config of earlier builds into an `AiSetup`.
import Foundation

/// The old configuration (`CredentialKey.translationApi`) held one provider with its key and model, switched on or off.
/// It becomes one saved provider; translation runs on it with that model when it was switched on, else on OpenCode with
/// its default. AI in chat follows translation, as it did. A config without an endpoint brings no provider.
public struct MigrateTranslationApiConfig: Sendable {
    public init() {}

    public func callAsFunction(_ old: TranslationApiConfig) -> AiSetup {
        let baseUrl = old.baseUrl.trimmingCharacters(in: .whitespaces)
        guard !baseUrl.isEmpty else { return .empty }
        let preset = TranslationApiPreset.byId(old.presetId)
        let name = preset.id == TranslationApiPreset.custom.id ? AiSettingsLogic.host(of: baseUrl) ?? preset.name : preset.name
        let provider = AiProvider(id: AiSetupEditing.newProviderId(presetId: preset.id, existing: []), presetId: preset.id,
                                  name: name, baseUrl: baseUrl, apiKey: old.apiKey.trimmingCharacters(in: .whitespaces))
        let model = old.model.trimmingCharacters(in: .whitespaces)
        let translation = old.enabled && !model.isEmpty ? AiModelChoice(providerId: provider.id, model: model) : .openCodeDefault
        return AiSetup(providers: [provider], translation: translation, chat: nil)
    }
}
