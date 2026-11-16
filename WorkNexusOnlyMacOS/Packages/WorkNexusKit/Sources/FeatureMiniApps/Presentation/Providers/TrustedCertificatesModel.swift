import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/mini_apps/presentation/providers/trusted_certificates_controller.dart
/// The sites the user chose to trust despite their certificate, for the settings list that forgets them and the edit dialog's
/// switch that trusts one up front. (The pages read the repository afresh when a certificate is refused, so a change here
/// applies at once.) Each change answers whether it was kept; the list then stays as it was if not.
@MainActor @Observable
final class TrustedCertificatesModel {
    private(set) var items: [TrustedCertificate] = []
    private let repository: TrustedCertificateRepository

    init(repository: TrustedCertificateRepository) { self.repository = repository }

    func load() async { apply(await repository.all()) }

    func isTrusted(_ origin: String) -> Bool { items.contains { $0.origin == origin } }

    func trust(origin: String, error: String) async -> Bool { apply(await repository.trust(origin: origin, error: error)) }
    func forget(_ certificate: TrustedCertificate) async -> Bool { apply(await repository.forget(certificate)) }
    func forgetAll() async -> Bool { apply(await repository.forgetAll()) }

    @discardableResult
    private func apply(_ result: Outcome<[TrustedCertificate]>) -> Bool {
        guard case .success(let list) = result else { return false }
        items = list
        return true
    }
}
