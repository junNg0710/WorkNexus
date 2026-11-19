import CoreUI
import SwiftUI

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_app_checklist.dart
/// This Mac's apps, each ticked when it is opened as the switch goes off — tick as many as you like. Ticked ones come first
/// (in the order picked: the first ends up in front); a search narrows the rest.
struct PanicAppChecklist: View {
    /// Room for about eight apps before the list scrolls.
    static let maxHeight: CGFloat = 280

    @Environment(\.appTheme) private var theme
    @State private var query = ""
    let apps: PanicSwitchModel.Apps
    let config: PanicSwitchConfig
    let save: PanicSave

    var body: some View {
        if apps == .failed {
            AppInlineNote(appString("panicSwitchAppsFailed", "Could not list the apps on this computer."), isError: true)
        } else {
            VStack(alignment: .leading, spacing: theme.spacing.s10) {
                AppSearchField(text: $query, hint: appString("panicSwitchSearchApps", "Search apps"))
                if apps == .loading {
                    AppInlineSpinner()
                } else if shown.isEmpty {
                    AppInlineNote(appString("panicSwitchNoMatches", "No matches"))
                } else {
                    ScrollView {
                        // Lazy: the icons are read only for the rows in view.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(shown, id: \.id) { app in
                                PanicCheckRow(label: app.name, picked: pickedIds.contains(app.id), onToggle: { toggle(app) }) {
                                    PanicAppIcon(app: app)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: Self.maxHeight).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var pickedIds: Set<String> { Set(config.appsToOpen.map(\.id)) }

    /// The picked apps first, then the rest, both narrowed by the search.
    private var shown: [AppRef] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func matches(_ a: AppRef) -> Bool { q.isEmpty || a.name.lowercased().contains(q) }
        let picked = pickedIds
        var all: [AppRef] = []
        if case .loaded(let list) = apps { all = list }
        return config.appsToOpen.filter(matches) + all.filter { !picked.contains($0.id) && matches($0) }
    }

    private func toggle(_ app: AppRef) {
        save { c in
            if c.appsToOpen.contains(where: { $0.id == app.id }) { c.appsToOpen.removeAll { $0.id == app.id } }
            else { c.appsToOpen.append(app) }
        }
    }
}

/// An app's own icon, or a generic window when it has none.
private struct PanicAppIcon: View {
    @Environment(\.appTheme) private var theme
    let app: AppRef

    var body: some View {
        if let icon = PanicAppIcons.image(for: app.id) {
            icon.resizable().interpolation(.high).frame(width: theme.sizes.icon20, height: theme.sizes.icon20)
        } else {
            Image(systemName: "macwindow").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx3)
                .frame(width: theme.sizes.icon20, height: theme.sizes.icon20)
        }
    }
}
