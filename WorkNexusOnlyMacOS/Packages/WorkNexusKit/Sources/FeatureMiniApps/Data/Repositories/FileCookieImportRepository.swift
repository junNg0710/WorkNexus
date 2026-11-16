import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/data/repositories/local_cookie_import_repository.dart
/// The imported sites in a JSON file (never the cookie values), one entry per site, the latest import winning.
public actor FileCookieImportRepository: CookieImportRepository {
    private let store: CookieImportStore

    public init(file: URL) { store = CookieImportStore(file: JSONListFile(url: file)) }

    public func all() async -> Outcome<[CookieImport]> {
        do { return .success(try store.read()) } catch { return .failure(.storage("Could not read the imported sites")) }
    }

    public func save(_ imports: [CookieImport]) async -> Outcome<[CookieImport]> {
        change { current in
            let sites = Set(imports.map(\.site))
            return current.filter { !sites.contains($0.site) } + imports
        }
    }

    public func forget(site: String) async -> Outcome<[CookieImport]> { change { $0.filter { $0.site != site } } }

    private func change(_ body: ([CookieImport]) -> [CookieImport]) -> Outcome<[CookieImport]> {
        do {
            let items = body(try store.read())
            try store.write(items)
            return .success(items)
        } catch { return .failure(.storage("Could not save the imported sites")) }
    }
}
