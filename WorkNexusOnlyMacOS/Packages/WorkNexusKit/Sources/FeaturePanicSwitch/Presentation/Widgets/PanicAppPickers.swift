import CoreUI
import SwiftUI

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_app_pickers.dart
/// The app brought forward: picked from the apps on this Mac, removable.
struct PanicTargetAppPicker: View {
    let apps: PanicSwitchModel.Apps
    let config: PanicSwitchConfig
    let save: (@escaping (inout PanicSwitchConfig) -> Void) -> Void

    var body: some View {
        PanicAppPicker(apps: apps, picked: config.targetApp.map { [$0] } ?? [],
                       hint: appString("panicSwitchPickApp", "Pick an app"),
                       onAdd: { app in save { $0.targetApp = app } },
                       onRemove: { _ in save { $0.targetApp = nil } })
    }
}

/// The apps hidden alongside: any number, each removable.
struct PanicHiddenAppsPicker: View {
    let apps: PanicSwitchModel.Apps
    let config: PanicSwitchConfig
    let save: (@escaping (inout PanicSwitchConfig) -> Void) -> Void

    var body: some View {
        PanicAppPicker(apps: apps, picked: config.appsToHide, hint: appString("panicSwitchAddApp", "Add an app"),
                       onAdd: { app in save { c in if !c.appsToHide.contains(where: { $0.id == app.id }) { c.appsToHide.append(app) } } },
                       onRemove: { app in save { $0.appsToHide.removeAll { $0.id == app.id } } })
    }
}

/// The picked apps as chips over a searchable list of this Mac's apps, each with its icon.
private struct PanicAppPicker: View {
    @Environment(\.appTheme) private var theme
    let apps: PanicSwitchModel.Apps
    let picked: [AppRef]
    let hint: String
    let onAdd: (AppRef) -> Void
    let onRemove: (AppRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s10) {
            if !picked.isEmpty {
                FlowLayout(spacing: theme.spacing.s6) {
                    ForEach(picked, id: \.id) { app in PanicAppChip(app: app) { onRemove(app) } }
                }
            }
            if apps == .failed {
                PanicNote(text: appString("panicSwitchAppsFailed", "Could not list the apps on this computer."))
            } else {
                SearchableDropdownField(items: list, value: nil, labelOf: \.name, hintText: hint,
                                        searchHint: appString("panicSwitchSearch", "Search…"),
                                        emptyLabel: appString("panicSwitchNoMatches", "No matches"),
                                        imageOf: { PanicAppIcons.image(for: $0.id) }, onChanged: onAdd)
            }
        }
    }

    private var list: [AppRef] {
        if case .loaded(let all) = apps { return all }
        return []
    }
}

/// A picked app: its icon, its name and a button that takes it off.
private struct PanicAppChip: View {
    @Environment(\.appTheme) private var theme
    let app: AppRef
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s6) {
            if let icon = PanicAppIcons.image(for: app.id) {
                icon.resizable().interpolation(.high).frame(width: theme.sizes.icon16, height: theme.sizes.icon16)
            } else {
                Image(systemName: "app").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx2)
            }
            Text(app.name).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.sm))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}
