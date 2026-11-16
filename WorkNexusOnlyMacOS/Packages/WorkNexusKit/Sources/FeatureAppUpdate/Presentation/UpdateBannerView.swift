import CoreUI
import SwiftUI

/// Ported from: lib/features/app_update/presentation/widgets/update_rail_button.dart (+ update_dialog.dart's progress)
/// A slim banner: hidden until a newer release is known; shows download progress, then "Update & restart"; a release
/// without an in-app build (or a failed install) opens its release page instead.
public struct UpdateBannerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL
    private let model: UpdateModel

    public init(model: UpdateModel) { self.model = model }

    public var body: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .downloading(_, let progress):
            Row(icon: "arrow.down.circle", message: String(localized: "updateDownloading")) {
                ProgressView(value: progress).frame(width: 90).tint(theme.colors.accent)
            }
        case .ready(let update, _):
            Row(icon: "arrow.up.circle.fill", message: Self.format("updateRestartToUpdate", update.latestVersion)) {
                AppButton(String(localized: "updateRestartNow"), kind: .primary) { Task { await model.installAndRestart() } }
            }
        case .installing:
            Row(icon: "arrow.up.circle.fill", message: String(localized: "updateRestarting")) { ProgressView().controlSize(.small) }
        case .manual(let update):
            Row(icon: "arrow.up.circle", message: Self.format("updateAvailable", update.latestVersion)) {
                releaseButton(update.releaseUrl)
            }
        case .failed(let update, _):
            Row(icon: "exclamationmark.triangle", message: String(localized: "updateInstallFailed")) {
                releaseButton(update.releaseUrl)
            }
        }
    }

    @ViewBuilder private func releaseButton(_ url: String) -> some View {
        if let target = URL(string: url) {
            AppButton(String(localized: "updateOpenReleasePage")) { openURL(target) }
        }
    }

    static func format(_ key: String.LocalizationValue, _ arg: String) -> String {
        String(format: String(localized: key), arg)
    }
}

private struct Row<Trailing: View>: View {
    @Environment(\.appTheme) private var theme
    let icon: String
    let message: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: theme.spacing.s10) {
            Image(systemName: icon).foregroundStyle(theme.colors.accent)
            Text(message).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).lineLimit(2)
            Spacer(minLength: theme.spacing.s8)
            trailing
        }
        .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s8)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}
