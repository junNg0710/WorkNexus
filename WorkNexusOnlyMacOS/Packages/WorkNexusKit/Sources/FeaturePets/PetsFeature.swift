import Foundation

/// Public entry point of FeaturePets: the composition root builds the pet services once and hands them to the gallery and
/// to whatever shows the chosen pet. Not in the Flutter app.
public enum PetsFeature {
    public static let name = "FeaturePets"

    /// The use cases of the pet gallery and library.
    public struct Services: Sendable {
        public let browse: BrowsePets
        public let listInstalled: ListInstalledPets
        public let install: InstallPet
        public let remove: RemovePet

        public init(catalog: PetCatalogRepository, library: PetLibraryRepository) {
            browse = BrowsePets(catalog); listInstalled = ListInstalledPets(library)
            install = InstallPet(library); remove = RemovePet(library)
        }
    }

    /// - Parameter root: where installed pets live (`PlatformPaths.applicationSupport()/pets`).
    public static func makeServices(root: URL, session: URLSession = .shared) -> Services {
        let http = CodexPetsHTTP(session: session)
        return Services(catalog: CodexPetsCatalogRepository(source: http), library: DiskPetLibrary(root: root, source: http))
    }
}
