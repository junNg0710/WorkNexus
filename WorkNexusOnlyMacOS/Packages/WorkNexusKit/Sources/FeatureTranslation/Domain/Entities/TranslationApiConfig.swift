/// Ported from: lib/features/translation/domain/entities/translation_api_config.dart
/// How translations run when the user brings their own API key instead of the OpenCode CLI. `apiKey` is empty for
/// endpoints that need none (Ollama).
public struct TranslationApiConfig: Sendable, Equatable {
    public var presetId: String
    public var baseUrl: String
    public var model: String
    public var apiKey: String
    /// Off keeps the saved settings but translates through OpenCode again.
    public var enabled: Bool

    public init(presetId: String, baseUrl: String, model: String, apiKey: String = "", enabled: Bool = true) {
        self.presetId = presetId; self.baseUrl = baseUrl; self.model = model; self.apiKey = apiKey; self.enabled = enabled
    }

    public var isUsable: Bool { enabled && !baseUrl.isEmpty && !model.isEmpty }
}
