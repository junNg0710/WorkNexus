import CoreDomain
import CryptoKit
import Foundation

/// Ported from: lib/features/mini_apps/domain/usecases/is_pinned_certificate.dart
/// Whether a server's certificate, given as DER bytes, is one the user already accepted elsewhere in the app (the chat
/// pins its server's self-signed certificate). A mini app's page that calls that server is let through only for that very
/// certificate, never for any other the system refuses.
public struct IsPinnedCertificate: Sendable {
    private let pins: PinnedCertificateSource
    public init(_ pins: PinnedCertificateSource) { self.pins = pins }

    public func callAsFunction(_ der: Data) async -> Bool {
        if der.isEmpty { return false }
        // Unreadable pins trust nothing: the system's answer stands.
        guard case .success(let set) = await pins.fingerprints(), !set.isEmpty else { return false }
        let seen = SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined()
        return set.contains(seen)
    }
}
