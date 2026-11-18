import CoreDomain
import Foundation

/// The catalogue of codex-pets.net. Not in the Flutter app.
public struct CodexPetsCatalogRepository: PetCatalogRepository {
    private let source: PetCatalogSource
    private let base: URL

    public init(source: PetCatalogSource, base: URL = CodexPetsHTTP.baseURL) {
        self.source = source; self.base = base
    }

    public func browse(_ query: PetQuery) async -> Outcome<PetCatalogPage> {
        await guarded {
            let data = try await source.fetchPage(query)
            let dto: PetPageDTO
            do { dto = try JSONDecoder().decode(PetPageDTO.self, from: data) }
            catch { throw Failure.parse("codex-pets.net sent a page the app cannot read") }
            return PetMappers.page(dto, base: base)
        }
    }
}
