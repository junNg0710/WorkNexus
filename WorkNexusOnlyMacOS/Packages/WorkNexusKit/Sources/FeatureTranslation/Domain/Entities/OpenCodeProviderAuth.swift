/// Ported from: lib/features/translation/domain/entities/opencode_provider_auth.dart
/// How one OpenCode provider is signed in, as OpenCode's own credential store records it. The key itself never leaves
/// the data layer: only `keyPreview` — a masked tail such as `••••••a1b2` — does.
public struct OpenCodeProviderAuth: Sendable, Equatable {
    /// Whether OpenCode has any credentials for the provider.
    public var linked: Bool
    /// Set for an API key; nil for a login only `opencode auth login` can refresh (OAuth), or when `linked` is false.
    public var keyPreview: String?

    public init(linked: Bool, keyPreview: String? = nil) { self.linked = linked; self.keyPreview = keyPreview }
    public static let none = OpenCodeProviderAuth(linked: false)
}
