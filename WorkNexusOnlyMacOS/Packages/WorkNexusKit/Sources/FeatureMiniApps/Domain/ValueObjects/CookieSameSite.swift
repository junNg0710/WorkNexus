/// Ported from: lib/features/mini_apps/domain/value_objects/cookie_same_site.dart
/// A cookie's SameSite policy; `unspecified` when the browser kept none.
public enum CookieSameSite: Sendable, Equatable, Hashable { case unspecified, none, lax, strict }
