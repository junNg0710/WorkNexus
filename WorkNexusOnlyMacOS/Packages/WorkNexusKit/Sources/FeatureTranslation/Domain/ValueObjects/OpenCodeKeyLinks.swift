import Foundation
/// Ported from: lib/features/translation/domain/value_objects/opencode_key_links.dart
/// Where to create an API key for an OpenCode provider id. Providers not listed fall back to OpenCode's own console.
public let openCodeConsoleUrl = "https://opencode.ai/auth"

private let keyPages: [String: String] = [
    "opencode": openCodeConsoleUrl,
    "opencode-go": openCodeConsoleUrl,
    "anthropic": "https://console.anthropic.com/settings/keys",
    "openai": "https://platform.openai.com/api-keys",
    "google": "https://aistudio.google.com/apikey",
    "openrouter": "https://openrouter.ai/keys",
    "deepseek": "https://platform.deepseek.com/api_keys",
    "groq": "https://console.groq.com/keys",
    "xai": "https://console.x.ai",
    "mistral": "https://console.mistral.ai/api-keys",
]

/// The page where `providerId` (case/space-insensitive) issues API keys.
public func openCodeKeyUrl(_ providerId: String) -> String {
    keyPages[providerId.trimmingCharacters(in: .whitespaces).lowercased()] ?? openCodeConsoleUrl
}

/// The OpenCode provider a `provider/model` id runs on — the one whose key the translation needs. OpenCode's own
/// default (no model pinned) is `opencode`.
public func openCodeProvider(of model: String) -> String {
    guard let slash = model.firstIndex(of: "/"), slash != model.startIndex else { return "opencode" }
    return String(model[..<slash])
}
