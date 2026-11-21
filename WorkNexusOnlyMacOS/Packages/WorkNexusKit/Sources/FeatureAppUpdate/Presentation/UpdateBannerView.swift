import CoreUI
import SwiftUI

/// Ported from: lib/features/app_update/presentation/widgets/update_rail_button.dart (+ update_dialog.dart's progress and
/// release notes)
/// A slim banner: hidden until a newer release is known; shows download progress, then "Update & restart"; a release
/// without an in-app build (or a failed install) opens its release page instead. "What's new" shows the notes of every
/// release between the running version and the new one.
public struct UpdateBannerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var notesOf: AvailableUpdate?
    private let model: UpdateModel

    public init(model: UpdateModel) { self.model = model }

    public var body: some View {
        // One container for every state, so the notes dialog stays open while the download moves on to "ready".
        VStack(spacing: 0) { content }
            .appDialog(item: $notesOf) { update in
                ReleaseNotesDialog(title: appString("updateDialogHeadline", "A new version of WorkNexus is available"),
                                   from: update.currentVersion, to: update.latestVersion,
                                   notes: LocalizedReleaseNotes.pick(update.releaseNotes, language: AppLanguage.current)) { notesOf = nil }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .downloading(let update, let progress):
            Row(icon: "arrow.down.circle", message: String(localized: "updateDownloading")) {
                notesButton(update)
                ProgressView(value: progress).frame(width: 90).tint(theme.colors.accent)
            }
        case .ready(let update, _):
            Row(icon: "arrow.up.circle.fill", message: Self.format("updateRestartToUpdate", update.latestTag)) {
                notesButton(update)
                AppButton(String(localized: "updateRestartNow"), kind: .primary) { Task { await model.installAndRestart() } }
            }
        case .installing:
            Row(icon: "arrow.up.circle.fill", message: String(localized: "updateRestarting")) { ProgressView().controlSize(.small) }
        case .manual(let update):
            Row(icon: "arrow.up.circle", message: Self.format("updateAvailable", update.latestTag)) {
                notesButton(update)
                releaseButton(update.releaseUrl)
            }
        case .failed(let update, _):
            Row(icon: "exclamationmark.triangle", message: String(localized: "updateInstallFailed")) {
                releaseButton(update.releaseUrl)
            }
        }
    }

    /// "What's new": the notes of every release since the running one (`CheckForUpdate`); none when nothing was written.
    @ViewBuilder private func notesButton(_ update: AvailableUpdate) -> some View {
        if !update.releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppButton(appString("updateWhatsNew", "What's new"), systemImage: "sparkles") { notesOf = update }
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
