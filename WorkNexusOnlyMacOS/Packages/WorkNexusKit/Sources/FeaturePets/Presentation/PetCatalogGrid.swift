import CoreUI
import SwiftUI

/// The search, the kind and the order of the catalogue. Not in the Flutter app.
struct PetGalleryToolbar: View {
    @Environment(\.appTheme) private var theme
    @Bindable var gallery: PetGalleryModel

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            AppSearchField(text: $gallery.text, hint: appString("petSearch", "Search pets"))
            HStack(spacing: theme.spacing.s8) {
                AppSegmentedTabs([AppSegmentedTab(label: appString("petKindAll", "All"), active: gallery.kind == nil) { gallery.kind = nil }]
                    + PetKind.allCases.map { k in AppSegmentedTab(label: Self.label(k), active: gallery.kind == k) { gallery.kind = k } })
                Spacer(minLength: theme.spacing.s8)
                AppSegmentedTabs(PetQuery.Sort.allCases.map { s in
                    AppSegmentedTab(label: Self.label(s), active: gallery.sort == s) { gallery.sort = s }
                })
            }
        }
    }

    static func label(_ kind: PetKind) -> String {
        switch kind {
        case .person: appString("petKindPerson", "People")
        case .animal: appString("petKindAnimal", "Animals")
        case .object: appString("petKindObject", "Objects")
        case .creature: appString("petKindCreature", "Creatures")
        }
    }

    static func label(_ sort: PetQuery.Sort) -> String {
        switch sort {
        case .popular: appString("petSortPopular", "Popular")
        case .new: appString("petSortNew", "New")
        case .random: appString("petSortRandom", "Surprise me")
        }
    }
}

/// The catalogue's pets, a page at a time: the next page loads as the last card comes into view.
struct PetCatalogGrid: View {
    @Environment(\.appTheme) private var theme
    let gallery: PetGalleryModel
    let library: PetLibraryModel
    let selectedId: String?
    let onSelect: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s10) {
            if let error = gallery.error {
                HStack(spacing: theme.spacing.s8) {
                    AppInlineNote(error, isError: true)
                    AppButton(appString("retry", "Retry"), kind: .ghost) { Task { await gallery.reload() } }
                }
            } else if !gallery.isLoading, gallery.pets.isEmpty {
                AppInlineNote(appString("petNoResults", "No pets match this search."))
            }
            LazyVGrid(columns: PetCardMetrics.columns, alignment: .leading, spacing: theme.spacing.s10) {
                ForEach(gallery.pets) { pet in
                    PetCatalogCard(pet: pet, library: library, selected: selectedId == pet.id, onSelect: onSelect)
                        .onAppear { if pet.id == gallery.pets.last?.id { Task { await gallery.loadMore() } } }
                }
            }
            if gallery.isLoading { AppInlineSpinner().frame(maxWidth: .infinity) }
        }
    }
}

/// One catalogue pet: "Get" downloads it and shows it at once; once installed it can be chosen like any other.
struct PetCatalogCard: View {
    @Environment(\.appTheme) private var theme
    let pet: CatalogPet
    let library: PetLibraryModel
    let selected: Bool
    let onSelect: (String?) -> Void

    var body: some View {
        PetCard(name: pet.displayName, byline: pet.ownerHandle.isEmpty ? nil : "@\(pet.ownerHandle)", selected: selected) {
            PetPoster(url: pet.posterURL)
        } action: {
            if library.installing.contains(pet.id) {
                AppInlineSpinner().frame(height: theme.sizes.control32)
            } else if library.isInstalled(pet.id) {
                PetUseButton(selected: selected) { onSelect(pet.id) }
            } else {
                AppButton(appString("petGet", "Get"), systemImage: "arrow.down.circle", kind: .primary) {
                    Task { if await library.install(pet) { onSelect(pet.id) } }
                }
            }
        }
        .help(pet.description)
    }
}
