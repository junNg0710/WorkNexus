import Foundation

/// A page of `/api/pets`, as codex-pets.net sends it (only the fields used). Not in the Flutter app.
struct PetPageDTO: Decodable {
    var pets: [PetDTO]
    var page: Int?
    var total: Int?
    var totalPages: Int?
}

/// One pet of `/api/pets`.
struct PetDTO: Decodable {
    var id: String
    var displayName: String?
    var description: String?
    var kind: String?
    var tags: [String]?
    var ownerHandle: String?
    var likeCount: Int?
    var downloadCount: Int?
    var spriteVersionNumber: Int?
    var ownerShadowbanned: Bool?
    var spritesheetUrl: String?
    var posterUrl: String?
    var previewUrl: String?
}

/// The Codex `pet.json` of an installed pet, with what the app adds to it (where it came from, who made it, the poster).
/// Not in the Flutter app.
struct PetManifestDTO: Codable, Equatable {
    var id: String
    var displayName: String
    var description: String
    var spritesheetPath: String
    var spriteVersionNumber: Int?
    var source: String?
    var ownerHandle: String?
    var posterPath: String?
}
