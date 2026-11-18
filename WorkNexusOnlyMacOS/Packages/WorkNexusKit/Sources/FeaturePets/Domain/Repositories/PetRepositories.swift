import CoreDomain
import Foundation

/// The online catalogue of pets. Not in the Flutter app.
public protocol PetCatalogRepository: Sendable {
    func browse(_ query: PetQuery) async -> Outcome<PetCatalogPage>
}

/// The pets installed on this Mac. Not in the Flutter app.
public protocol PetLibraryRepository: Sendable {
    /// Installed pets, by name.
    func list() async -> Outcome<[InstalledPet]>
    /// Downloads `pet` and keeps it; an installed pet of the same id is replaced. Nothing is left behind when it fails.
    func install(_ pet: CatalogPet) async -> Outcome<InstalledPet>
    func remove(id: String) async -> Outcome<Void>
}
