import CoreDomain
import Foundation

/// codex-pets.net DTOs → domain. Not in the Flutter app.
enum PetMappers {
    /// The page's pets the app can show: hidden creators (`ownerShadowbanned`) and pets without a usable sprite sheet are
    /// left out; URLs the API gives relative are resolved against `base`.
    static func page(_ dto: PetPageDTO, base: URL) -> PetCatalogPage {
        let pets = dto.pets.compactMap { pet($0, base: base) }
        let page = dto.page ?? 1
        return PetCatalogPage(pets: pets, page: page, totalPages: dto.totalPages ?? page, total: dto.total ?? pets.count)
    }

    static func pet(_ dto: PetDTO, base: URL) -> CatalogPet? {
        guard dto.ownerShadowbanned != true, PetID.isSafe(dto.id),
              let sheet = url(dto.spritesheetUrl, base: base) else { return nil }
        return CatalogPet(
            id: dto.id, displayName: dto.displayName?.nilIfBlank ?? dto.id, description: dto.description ?? "",
            kind: dto.kind.flatMap(PetKind.init(rawValue:)), tags: dto.tags ?? [], ownerHandle: dto.ownerHandle ?? "",
            likeCount: dto.likeCount ?? 0, downloadCount: dto.downloadCount ?? 0, spriteVersion: dto.spriteVersionNumber ?? 1,
            spritesheetURL: sheet, posterURL: url(dto.posterUrl, base: base), previewURL: url(dto.previewUrl, base: base))
    }

    /// An https URL, absolute or relative to `base`; nil for anything else.
    static func url(_ string: String?, base: URL) -> URL? {
        guard let string, !string.isEmpty, let u = URL(string: string, relativeTo: base)?.absoluteURL, u.scheme == "https" else { return nil }
        return u
    }

    static func manifest(_ pet: CatalogPet, spritesheetPath: String, posterPath: String?) -> PetManifestDTO {
        PetManifestDTO(id: pet.id, displayName: pet.displayName, description: pet.description, spritesheetPath: spritesheetPath,
                       spriteVersionNumber: pet.spriteVersion, source: "codex-pets.net", ownerHandle: pet.ownerHandle.nilIfBlank,
                       posterPath: posterPath)
    }

    static func installed(_ m: PetManifestDTO, folder: URL) -> InstalledPet {
        InstalledPet(id: m.id, displayName: m.displayName, description: m.description, ownerHandle: m.ownerHandle, source: m.source,
                     spriteVersion: m.spriteVersionNumber ?? 1, spritesheetURL: folder.appendingPathComponent(m.spritesheetPath),
                     posterURL: m.posterPath.map { folder.appendingPathComponent($0) })
    }
}

extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
