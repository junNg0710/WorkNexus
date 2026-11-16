import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/saved_filters_section.dart
/// The popover's "Saved filters": preset chips (tap applies, × deletes after confirming) and "Save current filter".
public struct SavedFiltersSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let controller: BoardController
    @State private var saving = false
    @State private var deleting: SavedFilter?

    public init(controller: BoardController) { self.controller = controller }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            AppSectionHeader(appString("savedFilters", "Saved filters"))
            if controller.savedFilters.isEmpty {
                AppInlineNote(appString("noSavedFiltersYet", "No presets yet — set up a filter, then save it."))
            } else {
                FlowLayout(spacing: theme.spacing.s6) {
                    ForEach(controller.savedFilters) { preset in
                        SavedFilterChip(preset: preset, applied: IsSavedFilterApplied()(preset, controller.filter),
                                        onApply: { controller.apply(preset) }, onDelete: { deleting = preset })
                    }
                }
            }
            AppButton(appString("saveCurrentFilter", "Save current filter"), systemImage: "plus", kind: .secondary) { saving = true }
                .disabled(!controller.filter.hasActiveFilters)
        }
        .padding(.bottom, theme.spacing.s14)
        .sheet(isPresented: $saving) { SaveFilterDialog(controller: controller) { saving = false } }
        .appConfirmDialog(isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                          title: appString("boardDeletePresetTitle", "Delete this preset?"),
                          message: appFormat("boardDeletePresetMessage", "“%1$@” will be removed from your saved filters.", deleting?.name ?? ""),
                          destructive: true) {
            guard let preset = deleting else { return }
            Task {
                if case .failure(let f) = await controller.deleteSavedFilter(preset.id) {
                    toasts?.show(appFormat("actionFailed", "Failed: %1$@", f.message), kind: .error)
                }
            }
        }
    }
}

private struct SavedFilterChip: View {
    @Environment(\.appTheme) private var theme
    let preset: SavedFilter; let applied: Bool; let onApply: () -> Void; let onDelete: () -> Void
    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onApply, selected: applied, height: theme.sizes.control32 - theme.spacing.s6,
                     fill: applied ? c.sel : c.panel2, border: theme.showOutline ? c.line : nil, cornerRadius: (theme.sizes.control32 - theme.spacing.s6) / 2) {
            HStack(spacing: theme.spacing.s4) {
                Text(preset.name).font(theme.typography.metaStrong).foregroundStyle(applied ? c.tx : c.tx2).lineLimit(1)
                Button(action: onDelete) { Image(systemName: "xmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3) }
                    .buttonStyle(.plain).help(appString("deleteSavedFilter", "Delete preset"))
            }
            .padding(.leading, theme.spacing.s12).padding(.trailing, theme.spacing.s8)
        }
    }
}

/// Ported from: lib/shared/board/presentation/widgets/save_filter_dialog.dart
public struct SaveFilterDialog: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController; let onClose: () -> Void
    @State private var name = ""
    @State private var error: String?
    @State private var saving = false

    public init(controller: BoardController, onClose: @escaping () -> Void) { self.controller = controller; self.onClose = onClose }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !saving else { return }
        saving = true; error = nil
        Task {
            let res = await controller.saveCurrentFilter(named: name)
            saving = false
            switch res {
            case .success: onClose()
            case .failure(let f): error = appFormat("actionFailed", "Failed: %1$@", f.message)
            }
        }
    }

    public var body: some View {
        let c = theme.colors
        AppDialogFrame(title: appString("saveFilterTitle", "Save filter"), maxWidth: theme.sizes.dialogSm, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                Text(appString("saveFilterNameLabel", "Name")).font(theme.typography.bodyStrong).foregroundStyle(c.tx2)
                TextField(appString("saveFilterNameHint", "e.g. My open blockers"), text: $name)
                    .textFieldStyle(.plain).font(theme.typography.body).padding(theme.spacing.s8)
                    .background(c.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(error == nil ? c.line : c.red, lineWidth: theme.borders.hairline))
                    .onSubmit(save).onChange(of: name) { error = nil }
                Text(error ?? appString("saveFilterExistsHint", "An existing name overwrites that preset."))
                    .font(theme.typography.caption).foregroundStyle(error == nil ? c.tx3 : c.red)
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("cancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(appString("save", "Save"), kind: .primary, action: save)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
        }
    }
}
