import CoreUI
import SwiftUI

/// Ported from: lib/features/app_update/presentation/widgets/{whats_new_dialog,update_version_change}.dart (+ the notes of
/// update_dialog.dart)
/// The versions jumped (`v1.9.0 → v1.9.5`) and, under them, the Markdown notes of every release in between. Shown once after
/// an update (What's new) and from the update banner before one ("What's new" in the coming version).
public struct ReleaseNotesDialog: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let from: String
    let to: String
    let notes: String
    let onClose: () -> Void
    /// Long notes (many releases) scroll inside the dialog instead of growing it past the window.
    static let notesMaxHeight: CGFloat = 420

    public init(title: String, from: String, to: String, notes: String, onClose: @escaping () -> Void) {
        self.title = title; self.from = from; self.to = to; self.notes = notes; self.onClose = onClose
    }

    /// The What's new dialog for `news` ("What's new in v1.9.5").
    public init(whatsNew news: WhatsNew, onClose: @escaping () -> Void) {
        self.init(title: appFormat("whatsNewTitle", "What's new in %1$@", ReleaseVersionPills.tag(news.to)),
                  from: news.from, to: news.to, notes: news.notes, onClose: onClose)
    }

    public var body: some View {
        AppDialogFrame(title: title, leadingIcon: "sparkles", maxWidth: theme.sizes.dialogLg, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s16) {
                ReleaseVersionPills(from: from, to: to)
                // As tall as the notes up to the limit, then scrolling.
                ViewThatFits(in: .vertical) {
                    notesText
                    ScrollView { notesText }
                }
                .frame(maxHeight: Self.notesMaxHeight)
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s16)
        } actions: {
            Spacer()
            AppButton(appString("gotIt", "Got it"), kind: .primary, action: onClose)
        }
    }

    private var notesText: some View {
        MarkdownText(notes).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
}

/// `v1.9.0 → v1.9.5`, as two pills so the new version stands out.
struct ReleaseVersionPills: View {
    @Environment(\.appTheme) private var theme
    let from: String
    let to: String

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            Pill(text: Self.tag(from), ink: theme.colors.tx2, strong: false)
            Image(systemName: "arrow.right").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx3)
            Pill(text: Self.tag(to), ink: theme.colors.accent, strong: true)
        }
    }

    /// `v1.9.5` for `1.9.5` and `v1.9.5+mac` alike.
    static func tag(_ version: String) -> String {
        AppVersion(version)?.tag ?? (version.hasPrefix("v") ? version : "v\(version)")
    }

    private struct Pill: View {
        @Environment(\.appTheme) private var theme
        let text: String
        let ink: Color
        let strong: Bool

        var body: some View {
            Text(text).font(theme.typography.metaStrong).foregroundStyle(ink)
                .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s4)
                .background(theme.colors.panel2, in: Capsule())
                .overlay(Capsule().stroke(strong ? ink : theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }
}
