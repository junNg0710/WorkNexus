import CoreDomain
import Foundation
import ImageIO

/// Installed pets, one folder each under `root` in the Codex layout (`<id>/pet.json`, `<id>/spritesheet.webp`, plus a
/// `poster.webp`). An install is written to a staging folder and moved into place only once the sheet checks out, so a
/// failed or cut-short download never leaves a half pet behind. Not in the Flutter app.
public final class DiskPetLibrary: PetLibraryRepository, @unchecked Sendable {
    /// The atlas sizes of the Codex pet format: v1 (9 rows) and v2 (11 rows) of 192 x 208 cells, 8 across.
    static let acceptedSizes: Set<PixelSize> = [PixelSize(width: 1536, height: 1872), PixelSize(width: 1536, height: 2288)]
    static let manifestName = "pet.json"
    static let stagingName = ".staging"

    private let root: URL
    private let source: PetCatalogSource
    private let fm = FileManager.default

    /// - Parameter root: the folder pets live in (the app passes `Application Support/<bundle id>/pets`).
    public init(root: URL, source: PetCatalogSource) {
        self.root = root; self.source = source
    }

    public func list() async -> Outcome<[InstalledPet]> {
        await guarded {
            guard fm.fileExists(atPath: root.path) else { return [] }
            // By name under `root`, so the URLs match the ones `install` hands out (no `/private` resolved in).
            let names = try fm.contentsOfDirectory(atPath: root.path).filter { !$0.hasPrefix(".") }
            return names.compactMap { readPet(in: root.appendingPathComponent($0)) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }

    public func install(_ pet: CatalogPet) async -> Outcome<InstalledPet> {
        await guarded {
            guard PetID.isSafe(pet.id) else { throw Failure.validation("Invalid pet id", fields: ["id": pet.id]) }
            let staging = root.appendingPathComponent(Self.stagingName).appendingPathComponent("\(pet.id)-\(UUID().uuidString)")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }

            let sheet = try await source.download(pet.spritesheetURL)
            try Task.checkCancellation()
            guard let size = Self.pixelSize(of: sheet), Self.acceptedSizes.contains(size) else {
                throw Failure.validation("This pet's sprite sheet is not in the Codex pet format", fields: ["id": pet.id])
            }
            let sheetName = "spritesheet." + Self.imageExtension(of: pet.spritesheetURL)
            try sheet.write(to: staging.appendingPathComponent(sheetName), options: .atomic)

            // The poster is only for the gallery: a pet without one still installs.
            var posterName: String?
            if let posterURL = pet.posterURL, let poster = try? await source.download(posterURL), Self.pixelSize(of: poster) != nil {
                let name = "poster." + Self.imageExtension(of: posterURL)
                try poster.write(to: staging.appendingPathComponent(name), options: .atomic)
                posterName = name
            }
            let manifest = PetMappers.manifest(pet, spritesheetPath: sheetName, posterPath: posterName)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: staging.appendingPathComponent(Self.manifestName), options: .atomic)
            try Task.checkCancellation()

            let destination = root.appendingPathComponent(pet.id)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: destination)
            }
            return PetMappers.installed(manifest, folder: destination)
        }
    }

    public func remove(id: String) async -> Outcome<Void> {
        await guarded {
            guard PetID.isSafe(id) else { throw Failure.validation("Invalid pet id", fields: ["id": id]) }
            let folder = root.appendingPathComponent(id)
            if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        }
    }

    /// The pet in `folder`, when it has a readable manifest naming a sheet that is there.
    private func readPet(in folder: URL) -> InstalledPet? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.manifestName)),
              let manifest = try? JSONDecoder().decode(PetManifestDTO.self, from: data),
              PetID.isSafe(manifest.id), !manifest.spritesheetPath.contains("/"),
              fm.fileExists(atPath: folder.appendingPathComponent(manifest.spritesheetPath).path) else { return nil }
        var pet = PetMappers.installed(manifest, folder: folder)
        if let poster = pet.posterURL, !fm.fileExists(atPath: poster.path) { pet.posterURL = nil }
        return pet
    }

    struct PixelSize: Hashable { var width: Int, height: Int }

    /// The pixel size of an image, read from its header (nothing is decoded); nil when it is not an image.
    static func pixelSize(of data: Data) -> PixelSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return PixelSize(width: w, height: h)
    }

    /// `webp` or `png`, from the URL; `webp` (what the format uses) for anything else.
    static func imageExtension(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext == "png" ? "png" : "webp"
    }
}
