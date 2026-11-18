import CoreUI
import SwiftUI

/// Choosing a pet: the ones on this Mac (the TBChat character first), then the codex-pets.net catalogue to search and
/// install from. Choosing one shows it at once (`onSelect`; nil is the TBChat character). Not in the Flutter app.
public struct PetGalleryView: View {
    @Environment(\.appTheme) private var theme
    let library: PetLibraryModel
    let gallery: PetGalleryModel
    let selectedId: String?
    let onSelect: (String?) -> Void

    public init(library: PetLibraryModel, gallery: PetGalleryModel, selectedId: String?, onSelect: @escaping (String?) -> Void) {
        self.library = library; self.gallery = gallery; self.selectedId = selectedId; self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s14) {
            PetSectionTitle(text: appString("petInstalled", "On this Mac"))
            PetInstalledGrid(library: library, selectedId: selectedId, onSelect: onSelect)
            if let error = library.lastError { AppInlineNote(error, isError: true) }
            PetSectionTitle(text: appString("petBrowse", "More pets from codex-pets.net"))
            PetGalleryToolbar(gallery: gallery)
            PetCatalogGrid(gallery: gallery, library: library, selectedId: selectedId, onSelect: onSelect)
            Text(appString("petCredit", "Pets are made and shared by the codex-pets.net community; each card names its creator."))
                .font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
        }
        // Typing is debounced; the first page, and a changed kind or order, load at once.
        .task(id: gallery.query) {
            if !gallery.pets.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await gallery.reloadIfChanged()
        }
    }
}

struct PetSectionTitle: View {
    @Environment(\.appTheme) private var theme
    let text: String
    var body: some View { Text(text).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx) }
}

/// A pet in a grid: its picture, its name, who made it, and one action.
struct PetCard<Picture: View, Action: View>: View {
    @Environment(\.appTheme) private var theme
    let name: String
    let byline: String?
    let selected: Bool
    @ViewBuilder let picture: () -> Picture
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: theme.spacing.s6) {
            picture()
                .frame(width: PetCardMetrics.pictureWidth, height: PetCardMetrics.pictureHeight)
            Text(name).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).lineLimit(1)
            Text(byline ?? " ").font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1)
            action()
        }
        .padding(theme.spacing.s8)
        .frame(maxWidth: .infinity)
        .background(selected ? theme.colors.sel : theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md)
            .strokeBorder(selected ? theme.colors.selLine : theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

enum PetCardMetrics {
    /// The picture keeps the sheet's 192 x 208 cell proportions.
    static let pictureWidth: CGFloat = 72, pictureHeight: CGFloat = 78
    static let minWidth: CGFloat = 120
    static var columns: [GridItem] { [GridItem(.adaptive(minimum: minWidth), spacing: 10)] }
}

/// A pet's still (a poster on disk or online); a paw while it loads or when there is none.
struct PetPoster: View {
    @Environment(\.appTheme) private var theme
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "pawprint").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx3)
            }
        }
    }
}
