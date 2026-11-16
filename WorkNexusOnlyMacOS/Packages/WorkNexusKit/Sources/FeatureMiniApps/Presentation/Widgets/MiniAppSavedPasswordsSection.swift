import CoreUI
import SwiftUI

/// New (no Dart counterpart): settings' "Saved passwords" — the sign-ins kept for the mini apps' sites (site and user only:
/// a password is never shown, nor read here), each with a way to delete it and one to delete them all, then the sites the
/// user never wants to be asked about, each with a way to be asked again.
struct MiniAppSavedPasswordsSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let model: WebLoginsSettingsModel
    @State private var confirmingAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s10) {
            if model.loadFailed {
                AppInlineNote(appString("miniAppPasswordsLoadFailed", "The saved passwords could not be read from the keychain."), isError: true)
            } else if model.items.isEmpty {
                AppInlineNote(appString("miniAppPasswordsEmpty", "No password saved yet. Sign in inside a mini app and choose Save."))
            } else {
                ForEach(model.items) { item in
                    SavedPasswordRow(title: item.host, detail: item.username.isEmpty ? appString("miniAppPasswordNoUsername", "No user name") : item.username,
                                     icon: "key", help: appString("miniAppPasswordDelete", "Delete this password")) {
                        Task { report(await model.delete(item)) }
                    }
                }
                if model.items.count > 1 {
                    AppButton(appString("miniAppPasswordsDeleteAll", "Delete all passwords"), systemImage: "trash", kind: .danger) { confirmingAll = true }
                }
            }
            if !model.neverSave.isEmpty {
                Text(appString("miniAppPasswordsNeverTitle", "Never saved")).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
                    .padding(.top, theme.spacing.s4)
                ForEach(model.neverSave, id: \.self) { origin in
                    SavedPasswordRow(title: MiniAppPasswordSaveBar.site(origin), detail: appString("miniAppPasswordsNeverDetail", "You are not asked to save passwords here"),
                                     icon: "nosign", help: appString("miniAppPasswordsNeverRemove", "Ask again on this site")) {
                        Task { report(await model.allow(origin)) }
                    }
                }
            }
        }
        .task { await model.load() }
        .appConfirmDialog(isPresented: $confirmingAll, title: appString("miniAppPasswordsDeleteAllTitle", "Delete all saved passwords?"),
                          message: appString("miniAppPasswordsDeleteAllMessage", "Mini apps will no longer fill your sign-in forms. This cannot be undone."),
                          confirmLabel: appString("miniAppPasswordsDeleteConfirm", "Delete"), destructive: true) { Task { report(await model.deleteAll()) } }
    }

    /// Says so when a change could not be kept; the list then shows what is really there.
    private func report(_ kept: Bool) {
        if !kept { toasts?.show(appString("miniAppPasswordsChangeFailed", "Couldn't change the saved passwords."), kind: .error) }
    }
}

/// One line of the section: what it is, a second line under it, and the button that removes it.
private struct SavedPasswordRow: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let detail: String
    let icon: String
    let help: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s12) {
            Image(systemName: icon).font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx3).frame(width: theme.sizes.icon24)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1).truncationMode(.middle)
                Text(detail).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AppIconButton("xmark", help: help, action: onRemove)
        }
    }
}
