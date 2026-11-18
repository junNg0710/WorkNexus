import Foundation

/// A pet on this Mac, ready to show: its manifest (the Codex `pet.json`) and where its files are. Not in the Flutter app.
public struct InstalledPet: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var description: String
    public var ownerHandle: String?
    /// Where it came from (`codex-pets.net`), nil for one put there by hand.
    public var source: String?
    public var spriteVersion: Int
    /// The sprite sheet file (`spritesheet.webp`).
    public var spritesheetURL: URL
    public var posterURL: URL?

    public init(id: String, displayName: String, description: String, ownerHandle: String?, source: String?,
                spriteVersion: Int, spritesheetURL: URL, posterURL: URL?) {
        self.id = id; self.displayName = displayName; self.description = description; self.ownerHandle = ownerHandle
        self.source = source; self.spriteVersion = spriteVersion; self.spritesheetURL = spritesheetURL; self.posterURL = posterURL
    }
}
