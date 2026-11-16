/// Ported from: lib/features/mini_apps/domain/value_objects/cookie_key.dart
/// What tells one cookie from another: who it is for and its name. Kept, without the value, to see later whether an
/// imported cookie is still there. `host` has no leading dot.
public struct CookieKey: Sendable, Equatable, Hashable {
    public var host: String
    public var path: String
    public var name: String
    public init(host: String, path: String, name: String) { self.host = host; self.path = path; self.name = name }
}
