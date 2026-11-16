/// The `TrustedCertificate.error` of a site trusted from its mini app's settings, before any certificate was refused.
public let trustedByChoice = "trusted-by-choice"

/// Ported from: lib/features/mini_apps/domain/entities/trusted_certificate.dart
/// A site whose invalid certificate the user chose to trust: the `origin` (`https://host:port`) and the `error` its
/// certificate was refused with when they trusted it, kept to say in Settings what was accepted. Trust is for the site:
/// while its page is shown, certificate errors of every kind are accepted. Forget the site to be asked again.
public struct TrustedCertificate: Sendable, Equatable, Hashable {
    public var origin: String
    public var error: String
    public init(origin: String, error: String) { self.origin = origin; self.error = error }
}
