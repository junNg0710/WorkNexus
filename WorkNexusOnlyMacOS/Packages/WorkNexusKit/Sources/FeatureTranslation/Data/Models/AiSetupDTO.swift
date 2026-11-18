/// Not in the Flutter app: the stored JSON of `AiSetup` (credential-store item `CredentialKey.aiSetup`); never leaves `Data/`.
import Foundation

/// `{"version":1,"providers":[{"id","preset","name","baseUrl","apiKey"}],"translation":{"provider","model"},"chat":{…}}`;
/// `chat` absent means "same as translation". Unknown fields are ignored and missing ones default, so an older or newer
/// build reads what it can.
struct AiSetupDTO: Codable, Equatable {
    struct Provider: Codable, Equatable {
        var id: String
        var preset: String?
        var name: String?
        var baseUrl: String?
        var apiKey: String?
    }

    struct Choice: Codable, Equatable {
        var provider: String
        var model: String?
    }

    static let currentVersion = 1
    var version: Int?
    var providers: [Provider]?
    var translation: Choice?
    var chat: Choice?
}

extension AiSetupDTO {
    init(_ s: AiSetup) {
        self.init(version: Self.currentVersion,
                  providers: s.providers.map { Provider(id: $0.id, preset: $0.presetId, name: $0.name, baseUrl: $0.baseUrl, apiKey: $0.apiKey) },
                  translation: Choice(s.translation), chat: s.chat.map(Choice.init))
    }

    var setup: AiSetup {
        let list = (providers ?? []).filter { !$0.id.isEmpty && $0.id != AiModelChoice.openCodeId }.map { p in
            let preset = TranslationApiPreset.byId(p.preset ?? TranslationApiPreset.custom.id)
            return AiProvider(id: p.id, presetId: preset.id, name: p.name ?? preset.name, baseUrl: p.baseUrl ?? preset.baseUrl, apiKey: p.apiKey ?? "")
        }
        return AiSetup(providers: list, translation: translation?.choice ?? .openCodeDefault, chat: chat?.choice)
    }
}

extension AiSetupDTO.Choice {
    init(_ c: AiModelChoice) { self.init(provider: c.providerId, model: c.model) }
    var choice: AiModelChoice { AiModelChoice(providerId: provider.isEmpty ? AiModelChoice.openCodeId : provider, model: model ?? "") }
}
