import CoreUI
import SwiftUI

/// New (no Dart counterpart): the bar under a mini app's toolbar once a sign-in form was sent — "Save password for <site>?"
/// (or "Update password…?" when that user is saved with another one) with Save, Never for this site and Not now. It is not
/// a dialog: the page stays usable, and nothing is kept unless Save is chosen. The password is never shown.
struct MiniAppPasswordSaveBar: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let passwords: MiniAppPasswordsModel

    var body: some View {
        if let offer = passwords.offer {
            // All three answers by name when there is room; in a narrow window "Not now" becomes a close button.
            ViewThatFits(in: .horizontal) {
                SaveBarRow(offer: offer, compact: false, onSave: { Task { await save() } }, onNever: { Task { await passwords.neverForSite() } },
                           onDismiss: { passwords.dismiss() })
                SaveBarRow(offer: offer, compact: true, onSave: { Task { await save() } }, onNever: { Task { await passwords.neverForSite() } },
                           onDismiss: { passwords.dismiss() })
            }
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s6)
            .background(theme.colors.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func save() async {
        if await passwords.saveOffer() { toasts?.show(appString("miniAppPasswordSaved", "Password saved in your keychain."), kind: .success) }
        else { toasts?.show(appString("miniAppPasswordSaveFailed", "Could not save the password."), kind: .error) }
    }

    /// The site as the bar names it: its host, or the whole origin when it is not encrypted, so that shows.
    static func site(_ origin: String) -> String { webOriginIsSecure(origin) ? webOriginHost(origin) : origin }

    static func title(_ offer: MiniAppPasswordsModel.Offer) -> String {
        offer.isUpdate ? appFormat("miniAppPasswordUpdateTitle", "Update the saved password for %1$@?", site(offer.origin))
                       : appFormat("miniAppPasswordSaveTitle", "Save password for %1$@?", site(offer.origin))
    }

    static func detail(_ offer: MiniAppPasswordsModel.Offer) -> String {
        let user = offer.username.isEmpty ? appString("miniAppPasswordNoUsername", "No user name") : offer.username
        let note = webOriginIsSecure(offer.origin) ? appString("miniAppPasswordKeychainNote", "Kept in your Mac's keychain")
                                                   : appString("miniAppPasswordInsecureNote", "This site is not encrypted")
        return "\(user) · \(note)"
    }
}

/// The bar's one line: what is asked, about whom, and the answers.
private struct SaveBarRow: View {
    @Environment(\.appTheme) private var theme
    let offer: MiniAppPasswordsModel.Offer
    let compact: Bool
    let onSave: () -> Void
    let onNever: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s10) {
            Image(systemName: "key.fill").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(MiniAppPasswordSaveBar.title(offer)).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                    .lineLimit(1).truncationMode(.middle)
                Text(MiniAppPasswordSaveBar.detail(offer)).font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
            if !compact {
                Spacer(minLength: theme.spacing.s12)
                AppButton(appString("miniAppPasswordNotNow", "Not now"), kind: .ghost, action: onDismiss)
            }
            AppButton(appString("miniAppPasswordNever", "Never for this site"), action: onNever)
            AppButton(offer.isUpdate ? appString("miniAppPasswordUpdate", "Update") : appString("save", "Save"), kind: .primary, action: onSave)
            if compact { AppIconButton("xmark", help: appString("miniAppPasswordNotNow", "Not now"), action: onDismiss) }
        }
    }
}
