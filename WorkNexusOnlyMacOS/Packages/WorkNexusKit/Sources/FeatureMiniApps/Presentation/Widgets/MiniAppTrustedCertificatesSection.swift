import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_trusted_certificates_section.dart
/// The sites whose invalid certificate the user chose to trust, each with a button to forget it, and one to forget them all.
struct MiniAppTrustedCertificatesSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let model: TrustedCertificatesModel

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s10) {
            if model.items.isEmpty {
                AppInlineNote(appString("miniAppTrustedCertsEmpty", "No site is trusted."))
            } else {
                ForEach(model.items, id: \.origin) { item in
                    HStack(spacing: theme.spacing.s16) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.origin).font(theme.typography.body).foregroundStyle(theme.colors.tx)
                            Text(Self.reason(item.error)).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        AppButton(appString("miniAppTrustedCertForget", "Forget"), systemImage: "xmark") { Task { report(await model.forget(item)) } }
                    }
                }
                if model.items.count > 1 {
                    AppButton(appString("miniAppTrustedCertsForgetAll", "Forget all"), systemImage: "trash", kind: .danger) {
                        Task { report(await model.forgetAll()) }
                    }
                }
            }
        }
        .task { await model.load() }
    }

    /// Says so when a change could not be saved; the list then stays as it was.
    private func report(_ kept: Bool) {
        if !kept { toasts?.show(appString("miniAppTrustedCertsSaveFailed", "Couldn't change the trusted sites."), kind: .error) }
    }

    /// The problem in a few words: the same ones the prompt used.
    static func reason(_ error: String) -> String {
        if error == trustedByChoice { return appString("miniAppTrustedCertByChoice", "Trusted from the mini app's settings, without a prompt") }
        switch CertificateProblem.of(error) {
        case .dates: return appString("certReasonDates", "has expired, or is not valid yet")
        case .name: return appString("certReasonName", "is issued for another site name")
        case .authority: return appString("certReasonAuthority", "is not issued by an authority this computer trusts")
        case .other: return appFormat("certReasonOther", "is not valid (%1$@)", error)
        }
    }
}
