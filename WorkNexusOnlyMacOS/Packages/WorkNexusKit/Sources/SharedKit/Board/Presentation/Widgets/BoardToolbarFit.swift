/// Ported from: lib/shared/board/presentation/widgets/board_toolbar_layout.dart (the degrade order).
import CoreGraphics

/// How the board toolbar fits its width, worked out from the widths of its pieces instead of laying out every
/// arrangement: `ViewThatFits` kept four full copies of the toolbar (each with its search field, Filters and Sort
/// buttons) and measured all of them on every update, which cost a slower Mac more than the board itself.
struct BoardToolbarFit: Equatable {
    /// One arrangement, from the widest to the narrowest.
    struct Layout: Equatable { var iconOnlyModes: Bool; var scopesAsMenu: Bool; var search: Bool }

    static let layouts = [
        Layout(iconOnlyModes: false, scopesAsMenu: false, search: true), Layout(iconOnlyModes: true, scopesAsMenu: false, search: true),
        Layout(iconOnlyModes: true, scopesAsMenu: true, search: true), Layout(iconOnlyModes: true, scopesAsMenu: true, search: false),
    ]

    /// The search field's narrowest width.
    static let searchMin: CGFloat = 160

    /// The pieces' own widths, measured as they are drawn.
    var scopesTabs: CGFloat = 0
    var scopesMenu: CGFloat = 0
    var modesWithLabels: CGFloat = 0
    var modesIconOnly: CGFloat = 0
    /// Filters, Sort and Refresh: the same in every arrangement.
    var others: CGFloat = 0

    /// The width `layout` takes: its pieces, the search field at its narrowest, and `spacing` between `pieces` of them.
    func width(of layout: Layout, searchMin: CGFloat, spacing: CGFloat, pieces: Int) -> CGFloat {
        let scopes = layout.scopesAsMenu ? scopesMenu : scopesTabs
        let modes = layout.iconOnlyModes ? modesIconOnly : modesWithLabels
        let gaps = CGFloat(max(pieces - 1, 0)) * spacing
        return scopes + others + modes + (layout.search ? searchMin : 0) + gaps
    }

    /// The widest arrangement that fits `available`; the narrowest when none does.
    func layout(available: CGFloat, searchMin: CGFloat, spacing: CGFloat, pieces: Int) -> Layout {
        Self.layouts.first { width(of: $0, searchMin: searchMin, spacing: spacing, pieces: pieces) <= available } ?? Self.layouts[3]
    }
}
