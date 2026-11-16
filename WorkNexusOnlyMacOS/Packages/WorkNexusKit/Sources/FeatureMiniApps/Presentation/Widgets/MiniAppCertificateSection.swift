import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_certificate_section.dart
/// The edit dialog's switch to trust the certificate of the site in `url` without being asked: the same trust the prompt
/// records, set up front. Shown for a secure address only.
struct MiniAppCertificateSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let url: String
    let model: TrustedCertificatesModel

    var body: some View {
        if let origin = MiniAppsModel.origin(of: URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))) {
            SettingsLikeSwitchRow(label: appString("miniAppCertAlwaysTrust", "Always trust this site's certificate"),
                                  hint: appString("miniAppCertAlwaysTrustHint", "Skips the certificate warning. Only use it for servers you run yourself."),
                                  isOn: model.isTrusted(origin)) { on in Task { await change(origin, on) } }
                .task { await model.load() }
        }
    }

    private func change(_ origin: String, _ on: Bool) async {
        let kept: Bool
        if on { kept = await model.trust(origin: origin, error: trustedByChoice) }
        else if let item = model.items.first(where: { $0.origin == origin }) { kept = await model.forget(item) }
        else { kept = true }
        if !kept { toasts?.show(appString("miniAppTrustedCertsSaveFailed", "Couldn't change the trusted sites."), kind: .error) }
    }
}

/// A label with a hint on the left and a switch on the right.
struct SettingsLikeSwitchRow: View {
    @Environment(\.appTheme) private var theme
    let label: String
    var hint: String?
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s12) {
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(label).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
                if let hint { Text(hint).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: theme.spacing.s12)
            Toggle("", isOn: Binding(get: { isOn }, set: onChange)).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}
