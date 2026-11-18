import CoreDomain
import Foundation

/// A page of the online catalogue: the search is trimmed, nothing is fetched past the last page. Not in the Flutter app.
public struct BrowsePets: Sendable {
    private let catalog: PetCatalogRepository
    public init(_ catalog: PetCatalogRepository) { self.catalog = catalog }

    public func callAsFunction(_ query: PetQuery) async -> Outcome<PetCatalogPage> {
        var q = query
        q.text = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return await catalog.browse(q)
    }
}

/// The pets on this Mac. Not in the Flutter app.
public struct ListInstalledPets: Sendable {
    private let library: PetLibraryRepository
    public init(_ library: PetLibraryRepository) { self.library = library }
    public func callAsFunction() async -> Outcome<[InstalledPet]> { await library.list() }
}

/// Downloads a catalogue pet onto this Mac. Not in the Flutter app.
public struct InstallPet: Sendable {
    private let library: PetLibraryRepository
    public init(_ library: PetLibraryRepository) { self.library = library }

    public func callAsFunction(_ pet: CatalogPet) async -> Outcome<InstalledPet> {
        guard PetID.isSafe(pet.id) else { return .failure(.validation("Invalid pet id", fields: ["id": pet.id])) }
        return await library.install(pet)
    }
}

/// Removes an installed pet. Not in the Flutter app.
public struct RemovePet: Sendable {
    private let library: PetLibraryRepository
    public init(_ library: PetLibraryRepository) { self.library = library }

    public func callAsFunction(id: String) async -> Outcome<Void> {
        guard PetID.isSafe(id) else { return .failure(.validation("Invalid pet id", fields: ["id": id])) }
        return await library.remove(id: id)
    }
}

/// A pet id names a folder on disk: letters, digits, `-`, `_` and `.` only, never `.`/`..`. Not in the Flutter app.
public enum PetID {
    public static func isSafe(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128, id != ".", id != "..", !id.hasPrefix(".") else { return false }
        return id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || "-_.".unicodeScalars.contains($0) }
    }
}
