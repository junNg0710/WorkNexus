import Foundation

/// A pet offered by the online catalogue (codex-pets.net), as the gallery lists it. Not in the Flutter app.
public struct CatalogPet: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var description: String
    /// person / animal / object / creature, when the catalogue says.
    public var kind: PetKind?
    public var tags: [String]
    /// Who made it, credited wherever the pet is shown.
    public var ownerHandle: String
    public var likeCount: Int
    public var downloadCount: Int
    /// 1 (9 animation rows) or 2 (with look directions).
    public var spriteVersion: Int
    public var spritesheetURL: URL
    /// A still of the pet, for the gallery grid.
    public var posterURL: URL?
    /// A short animated preview.
    public var previewURL: URL?

    public init(id: String, displayName: String, description: String, kind: PetKind?, tags: [String], ownerHandle: String,
                likeCount: Int, downloadCount: Int, spriteVersion: Int, spritesheetURL: URL, posterURL: URL?, previewURL: URL?) {
        self.id = id; self.displayName = displayName; self.description = description; self.kind = kind; self.tags = tags
        self.ownerHandle = ownerHandle; self.likeCount = likeCount; self.downloadCount = downloadCount
        self.spriteVersion = spriteVersion; self.spritesheetURL = spritesheetURL; self.posterURL = posterURL; self.previewURL = previewURL
    }
}

/// What a catalogue pet is (the catalogue's own filter).
public enum PetKind: String, Sendable, CaseIterable {
    case person, animal, object, creature
}
