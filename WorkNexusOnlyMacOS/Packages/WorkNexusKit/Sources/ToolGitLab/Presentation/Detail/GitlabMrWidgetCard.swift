import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/{mr_widget_card,mr_async_button,gitlab_mr_commands}.dart
/// The state-changing actions on a merge request: the detail runs each through its use case (after asking, for the ones
/// that change the branch); the panels and the header menu only trigger them. `busy` is the action in flight, so its
/// button shows a spinner and the others wait.
struct GitlabMrCommands {
    var busy: GitlabMrAction.Kind?
    var approve: () -> Void = {}
    var unapprove: () -> Void = {}
    var merge: (_ squash: Bool, _ removeSourceBranch: Bool) -> Void = { _, _ in }
    var rebase: () -> Void = {}
    var close: () -> Void = {}
    var reopen: () -> Void = {}
    /// Marks the MR as a draft (true) or ready for review (false).
    var setDraft: (Bool) -> Void = { _ in }
}

/// The shell of a GitLab-style merge-request widget (approvals, merge, merged / closed): a status icon, a one-line title
/// and its actions, over an optional inset details block. `tint` washes the header row (the merged state's band).
struct GitlabMrWidgetCard: View {
    @Environment(\.appTheme) private var theme
    let systemImage: String
    let iconColor: Color
    var tint: Color?
    let title: AnyView
    var actions: [AnyView] = []
    var details: AnyView?

    var body: some View {
        let c = theme.colors
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s10) {
                Image(systemName: systemImage).font(.system(size: theme.sizes.icon20)).foregroundStyle(iconColor)
                title.font(theme.typography.bodyStrong).foregroundStyle(c.tx).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(actions.enumerated()), id: \.offset) { $1 }
            }
            .padding(theme.spacing.s14).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.map { c.mix(c.card, $0, 0.08) } ?? .clear)
            if let details {
                details.font(theme.typography.paragraph).foregroundStyle(c.tx2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(theme.spacing.s14).background(c.panel2)
                    .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
            }
        }
        .background(c.card, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.line, lineWidth: theme.borders.hairline))
    }
}

/// One line of a widget's details block, bulleted.
struct GitlabMrDetailBullet<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s6) {
            Text(verbatim: "•")
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, theme.spacing.s4)
    }
}

/// A merge-request widget's action button: a spinner while its action runs, disabled while any action does.
struct GitlabMrButton: View {
    let label: String
    var secondary = false
    var loading = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        AppButton(label, kind: secondary ? .secondary : .primary, action: action)
            .opacity(loading ? 0 : 1)
            .overlay { if loading { ProgressView().controlSize(.small) } }
            .disabled(disabled || loading).opacity(disabled && !loading ? 0.5 : 1)
    }
}
