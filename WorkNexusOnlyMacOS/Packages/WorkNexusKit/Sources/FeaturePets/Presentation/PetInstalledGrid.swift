import CoreUI
import SwiftUI

/// The pets on this Mac: the TBChat character that ships with the app, then the installed ones (which can be removed).
/// Not in the Flutter app.
struct PetInstalledGrid: View {
    @Environment(\.appTheme) private var theme
    let library: PetLibraryModel
    let selectedId: String?
    let onSelect: (String?) -> Void
    @State private var tbchat = PetSpriteSheet.bundled()

    var body: some View {
        LazyVGrid(columns: PetCardMetrics.columns, alignment: .leading, spacing: theme.spacing.s10) {
            PetCard(name: "TBChat", byline: appString("petBuiltIn", "Built in"), selected: selectedId == nil) {
                if let frame = tbchat?.frame(.idle, 0) {
                    Image(decorative: frame, scale: 1).resizable().interpolation(.high).scaledToFit()
                }
            } action: {
                PetUseButton(selected: selectedId == nil) { onSelect(nil) }
            }
            ForEach(library.installed) { pet in
                PetCard(name: pet.displayName, byline: pet.ownerHandle.map { "@\($0)" }, selected: selectedId == pet.id) {
                    PetPoster(url: pet.posterURL)
                } action: {
                    HStack(spacing: theme.spacing.s4) {
                        PetUseButton(selected: selectedId == pet.id) { onSelect(pet.id) }
                        AppIconButton("trash", help: appString("petRemove", "Remove this pet")) {
                            if selectedId == pet.id { onSelect(nil) }
                            Task { await library.remove(pet.id) }
                        }
                    }
                }
            }
        }
    }
}

/// "Use" for a pet, or a check for the one shown.
struct PetUseButton: View {
    @Environment(\.appTheme) private var theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        if selected {
            Label(appString("petInUse", "In use"), systemImage: "checkmark")
                .font(theme.typography.meta).foregroundStyle(theme.colors.accent)
                .frame(height: theme.sizes.control32)
        } else {
            AppButton(appString("petUse", "Use"), kind: .secondary, action: action)
        }
    }
}
