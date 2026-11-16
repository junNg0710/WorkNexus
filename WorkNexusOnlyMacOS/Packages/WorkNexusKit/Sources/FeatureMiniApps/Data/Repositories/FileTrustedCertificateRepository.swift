import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/data/repositories/local_trusted_certificate_repository.dart
/// The trusted certificates in a JSON file. An actor, so changes follow one another and two trusts at once lose neither.
public actor FileTrustedCertificateRepository: TrustedCertificateRepository {
    private let store: TrustedCertificateStore

    public init(file: URL) { store = TrustedCertificateStore(file: JSONListFile(url: file)) }

    public func all() async -> Outcome<[TrustedCertificate]> {
        do { return .success(try store.read()) } catch { return .failure(.storage("Could not read the trusted certificates")) }
    }

    public func trust(origin: String, error: String) async -> Outcome<[TrustedCertificate]> {
        change { $0.filter { $0.origin != origin } + [TrustedCertificate(origin: origin, error: error)] }
    }

    public func forget(_ certificate: TrustedCertificate) async -> Outcome<[TrustedCertificate]> {
        change { $0.filter { $0 != certificate } }
    }

    public func forgetAll() async -> Outcome<[TrustedCertificate]> { change { _ in [] } }

    private func change(_ body: ([TrustedCertificate]) -> [TrustedCertificate]) -> Outcome<[TrustedCertificate]> {
        do {
            let items = body(try store.read())
            try store.write(items)
            return .success(items)
        } catch { return .failure(.storage("Could not save the trusted certificates")) }
    }
}
