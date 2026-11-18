/// Ported from: lib/features/translation/domain/value_objects/translation_api_preset.dart
/// A ready-made OpenAI-compatible endpoint the user can translate through with their own API key. Models are
/// suggestions: providers rename them, and the user can type any other.
public struct TranslationApiPreset: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// Root the `/chat/completions` path is appended to.
    public let baseUrl: String
    public let defaultModel: String
    /// Where the user creates a key; nil when none is needed.
    public let keyUrl: String?
    public let needsKey: Bool

    public init(id: String, name: String, baseUrl: String, defaultModel: String, keyUrl: String? = nil, needsKey: Bool = true) {
        self.id = id; self.name = name; self.baseUrl = baseUrl; self.defaultModel = defaultModel
        self.keyUrl = keyUrl; self.needsKey = needsKey
    }

    /// Not an endpoint: translating through the OpenCode CLI and its own login, offered alongside the presets so the
    /// user picks exactly one backend.
    public static let openCode = TranslationApiPreset(id: "opencode", name: "OpenCode", baseUrl: "", defaultModel: "", needsKey: false)
    public var isOpenCode: Bool { id == Self.openCode.id }

    public static let custom = TranslationApiPreset(id: "custom", name: "Custom", baseUrl: "", defaultModel: "")

    /// OpenAI, Anthropic, DeepSeek, Mistral and xAI are not in the Flutter app (macOS only).
    public static let all: [TranslationApiPreset] = [
        TranslationApiPreset(id: "openai", name: "OpenAI", baseUrl: "https://api.openai.com/v1",
                             defaultModel: "gpt-5-mini", keyUrl: "https://platform.openai.com/api-keys"),
        // Claude through Anthropic's OpenAI-compatible endpoint; it also wants `x-api-key` + `anthropic-version` headers.
        TranslationApiPreset(id: "anthropic", name: "Anthropic Claude", baseUrl: "https://api.anthropic.com/v1",
                             defaultModel: "claude-haiku-5-5", keyUrl: "https://console.anthropic.com/settings/keys"),
        TranslationApiPreset(id: "gemini", name: "Google Gemini", baseUrl: "https://generativelanguage.googleapis.com/v1beta/openai",
                             defaultModel: "gemini-3.8-flash", keyUrl: "https://aistudio.google.com/apikey"),
        TranslationApiPreset(id: "groq", name: "Groq", baseUrl: "https://api.groq.com/openai/v1",
                             defaultModel: "llama-3.3-70b-versatile", keyUrl: "https://console.groq.com/keys"),
        TranslationApiPreset(id: "deepseek", name: "DeepSeek", baseUrl: "https://api.deepseek.com/v1",
                             defaultModel: "deepseek-chat", keyUrl: "https://platform.deepseek.com/api_keys"),
        TranslationApiPreset(id: "mistral", name: "Mistral", baseUrl: "https://api.mistral.ai/v1",
                             defaultModel: "mistral-small-latest", keyUrl: "https://console.mistral.ai/api-keys"),
        TranslationApiPreset(id: "xai", name: "xAI Grok", baseUrl: "https://api.x.ai/v1",
                             defaultModel: "grok-4", keyUrl: "https://console.x.ai"),
        TranslationApiPreset(id: "openrouter", name: "OpenRouter", baseUrl: "https://openrouter.ai/api/v1",
                             defaultModel: "meta-llama/llama-3.3-70b-instruct:free", keyUrl: "https://openrouter.ai/keys"),
        TranslationApiPreset(id: "ollama", name: "Ollama (local)", baseUrl: "http://localhost:11434/v1",
                             defaultModel: "qwen2.5:7b", needsKey: false),
        custom,
    ]

    public static func byId(_ id: String) -> TranslationApiPreset { all.first { $0.id == id } ?? custom }
}
