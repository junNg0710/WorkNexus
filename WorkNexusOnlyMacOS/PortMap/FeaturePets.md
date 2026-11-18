# FeaturePets (macOS only → Sources/FeaturePets)

Not in the Flutter app. Pets in the Codex pet format (`pet.json` + an 8-column atlas of 192×208 cells: v1 1536×1872 with 9 animation rows, v2 1536×2288 adding 16 look directions), browsed and installed from the public codex-pets.net catalogue.

Public entry: `PetsFeature.makeServices(root:session:)` → `PetsFeature.Services` (`browse`, `listInstalled`, `install`, `remove`); `PetLibraryModel(services:)` (installed pets, `sheet(for:)`), `PetGalleryModel(services:)` (search / kind / order, paging), `PetGalleryView(library:gallery:selectedId:onSelect:)`.
Wired in `App/Sources/CompositionRoot.swift` (pets folder: `PlatformPaths.applicationSupport()/pets`) and `App/Sources/HostWiring.swift` (`ShellHost.petSheet`, `petAttention`, `revealApp`); settings page `App/Sources/Settings/PetSettingsPage.swift`.

Pets uploaded to codex-pets.net carry no redistribution terms, so none is bundled: each is downloaded only when the user asks, and its creator is shown on its card.

| Area | Swift |
|---|---|
| Catalogue pet, kind, query, page | Domain/Entities/{CatalogPet,PetQuery}.swift |
| Installed pet | Domain/Entities/InstalledPet.swift |
| Catalogue + library interfaces | Domain/Repositories/PetRepositories.swift |
| BrowsePets / ListInstalledPets / InstallPet / RemovePet, safe ids | Domain/UseCases/PetUseCases.swift |
| codex-pets.net HTTP (`/api/pets?page&pageSize&sort&q&kind`, https downloads, generic User-Agent) | Data/DataSources/CodexPetsHTTP.swift |
| DTOs (`/api/pets`, `pet.json`) + mappers (drops hidden creators, resolves relative URLs) | Data/Models/{PetDTOs,PetMappers}.swift |
| Catalogue repository | Data/Repositories/CodexPetsCatalogRepository.swift |
| Disk library (staging folder → atomic move, atlas size checked from the image header) | Data/Repositories/DiskPetLibrary.swift |
| Library + gallery models | Presentation/{PetLibraryModel,PetGalleryModel}.swift |
| Gallery (installed grid, toolbar, catalogue grid, cards) | Presentation/{PetGalleryView,PetInstalledGrid,PetCatalogGrid}.swift |
| Tests | Tests/FeaturePetsTests/{PetCatalogTests,DiskPetLibraryTests,PetGalleryModelTests}.swift (+ `Fixtures/pets-page.json`, a trimmed real page) |

Shared pieces outside the module:
- `CoreUI/Widgets/Pet/` — sprite sheet v1/v2 (`PetSpriteSheet`, look cells), `PetTiming` (steady for TBChat, Codex per-frame timings for downloaded pets), `PetDirector` moods (`calm` / `busy` / `offline` / `trouble` / `attention`) and reactions (`poke`, `notify`, `celebrate`, `done`, `gaze`), `PetView`.
- `CoreUI/Platform/FloatingPetPanel.swift` — the non-activating, see-through panel of the floating pet.
- `SharedKit/Presentation/Shell/PetLayer.swift` — picks the sheet, drives the director from sync status, unread chats, ZenTao notifications and celebrations, and shows the pet in the window or in the floating panel.
