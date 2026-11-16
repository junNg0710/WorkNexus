import CoreUI
import SwiftUI

/// New (no Dart counterpart): the toolbar's key button — the sign-ins saved for the site of the page on screen, each with
/// "fill" and "delete". It opens by itself when a sign-in form appears and several are saved for it, so the user picks one.
/// Passwords are not shown, and none is read until one is filled. Hidden on a page that is not on the web.
struct MiniAppPasswordButton: View {
    @Environment(\.appTheme) private var theme
    let browser: MiniAppBrowserModel
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        let passwords = browser.passwords
        let origin = webOrigin(ofAddress: browser.address)
        if origin != nil {
            let has = !passwords.saved.isEmpty
            Button { open = true } label: {
                Image(systemName: has ? "key.fill" : "key").font(.system(size: theme.sizes.icon16))
                    .foregroundStyle(has ? theme.colors.accent : (hovering ? theme.colors.tx : theme.colors.tx2))
                    .frame(width: theme.sizes.control32, height: theme.sizes.control32)
                    .background(hovering ? theme.colors.tx.opacity(0.08) : .clear, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).onHover { hovering = $0 }.help(appString("miniAppPasswordsButton", "Saved passwords for this site"))
            .task(id: origin) { await passwords.refresh(address: browser.address) }
            .onChange(of: passwords.chooserRequested, initial: true) { _, asked in
                if asked { passwords.chooserRequested = false; open = true }
            }
            .onChange(of: open) { _, shown in if shown { Task { await passwords.refresh(address: browser.address) } } }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                MiniAppPasswordList(passwords: passwords, site: origin.map(MiniAppPasswordSaveBar.site) ?? "") { open = false }
            }
        }
    }
}

/// The popover's content: the site, then its sign-ins.
struct MiniAppPasswordList: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let passwords: MiniAppPasswordsModel
    let site: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(appString("miniAppPasswordsTitle", "Saved passwords")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                Text(site).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1).truncationMode(.middle)
            }
            if passwords.saved.isEmpty {
                AppInlineNote(appString("miniAppPasswordsNoneForSite", "None saved for this site. Sign in on the page and choose Save."))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(passwords.saved) { item in
                    MiniAppPasswordRow(item: item, onFill: { Task { await fill(item) } }, onDelete: { Task { await passwords.delete(item) } })
                }
            }
        }
        .padding(theme.spacing.s12).frame(width: 300, alignment: .leading)
    }

    private func fill(_ item: WebLoginSummary) async {
        let filled = await passwords.fill(item)
        if filled { onClose() }
        else { toasts?.show(appString("miniAppPasswordsNoForm", "There is no sign-in form on this page."), kind: .error) }
    }
}

private struct MiniAppPasswordRow: View {
    @Environment(\.appTheme) private var theme
    let item: WebLoginSummary
    let onFill: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            Image(systemName: "person.crop.circle").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx3)
            Text(item.username.isEmpty ? appString("miniAppPasswordNoUsername", "No user name") : item.username)
                .font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            AppButton(appString("miniAppPasswordFill", "Fill"), action: onFill)
            AppIconButton("trash", help: appString("miniAppPasswordDelete", "Delete this password"), action: onDelete)
        }
    }
}
