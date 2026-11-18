/// Not in the Flutter app: several saved AI providers, and a provider + model per task.
import Foundation

/// What an AI run is for. Each purpose has its own provider + model choice; chat falls back to the translation one.
public enum AiPurpose: String, Sendable, CaseIterable {
    /// Ticket and chat-message translation.
    case translation
    /// The ✨ AI help in chat: summaries, reply ideas, rewrites.
    case chat
}

/// An OpenAI-compatible endpoint the user saved with their own key (OpenAI, Claude, Gemini, a local Ollama, …).
/// `apiKey` is empty for endpoints that need none.
public struct AiProvider: Sendable, Equatable, Identifiable {
    /// Stable id the model choices refer to (never `AiModelChoice.openCodeId`).
    public var id: String
    public var presetId: String
    /// What the user sees: the preset's name, or the name they typed for a custom endpoint.
    public var name: String
    /// Root the `/chat/completions` and `/models` paths are appended to.
    public var baseUrl: String
    public var apiKey: String

    public init(id: String, presetId: String, name: String, baseUrl: String, apiKey: String = "") {
        self.id = id; self.presetId = presetId; self.name = name; self.baseUrl = baseUrl; self.apiKey = apiKey
    }

    public var preset: TranslationApiPreset { TranslationApiPreset.byId(presetId) }

    /// The endpoint can be called: it has a URL, and a key when its preset needs one.
    public var isUsable: Bool {
        !baseUrl.trimmingCharacters(in: .whitespaces).isEmpty
            && (!preset.needsKey || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

/// The provider and model one purpose runs on.
public struct AiModelChoice: Sendable, Equatable, Hashable {
    /// The built-in OpenCode CLI (its own login and model list), not a saved provider.
    public static let openCodeId = "opencode"
    public static let openCodeDefault = AiModelChoice(providerId: openCodeId, model: "")
    /// The built-in Claude Code CLI (`claude -p`): the user's own Claude login, no API key.
    public static let claudeCodeId = "claudecode"

    /// `openCodeId` or an `AiProvider.id`.
    public var providerId: String
    /// Empty: the backend's default (OpenCode's configured model, or the provider preset's suggested one).
    public var model: String

    public init(providerId: String, model: String = "") { self.providerId = providerId; self.model = model }

    public var isOpenCode: Bool { providerId == Self.openCodeId }
    public var isClaudeCode: Bool { providerId == Self.claudeCodeId }
}

/// Every saved provider and what each purpose runs on. Stored whole, key included, as one credential-store item.
public struct AiSetup: Sendable, Equatable {
    public var providers: [AiProvider]
    public var translation: AiModelChoice
    /// nil: AI in chat uses the translation choice.
    public var chat: AiModelChoice?

    public init(providers: [AiProvider] = [], translation: AiModelChoice = .openCodeDefault, chat: AiModelChoice? = nil) {
        self.providers = providers; self.translation = translation; self.chat = chat
    }

    /// Nothing saved: OpenCode for everything.
    public static let empty = AiSetup()

    public func provider(_ id: String) -> AiProvider? { providers.first { $0.id == id } }

    /// The choice as saved for `purpose` (chat inherits translation when it has none of its own).
    public func choice(for purpose: AiPurpose) -> AiModelChoice {
        switch purpose {
        case .translation: translation
        case .chat: chat ?? translation
        }
    }
}
