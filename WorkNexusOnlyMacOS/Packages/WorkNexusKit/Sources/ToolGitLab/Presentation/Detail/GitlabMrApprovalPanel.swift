import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_mr_approval_panel.dart
/// GitLab's approval widget: who approved (or how many approvals are still needed) and, while the MR is open, Approve /
/// Revoke approval. A merged MR keeps the record of who approved; a closed one shows nothing.
struct GitlabMrApprovalPanel: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let entity: GitLabItemEntity
    let commands: GitlabMrCommands
    let avatarLoader: AvatarLoader

    /// Whether the widget has anything to show for this MR.
    static func shows(_ ticket: Ticket, _ entity: GitLabItemEntity) -> Bool {
        switch GitlabMrPhase.of(ticket, entity) {
        case .closed: false
        case .merged: !entity.approvedBy.isEmpty
        case .draft, .open: true
        }
    }

    var body: some View {
        let c = theme.colors
        if Self.shows(ticket, entity) {
            let open = GitlabMrPhase.of(ticket, entity).isActive
            let approvers = entity.approvedBy
            let youApproved = entity.userHasApproved ?? false
            let left = entity.approvalsLeft ?? 0
            let busy = commands.busy
            GitlabMrWidgetCard(
                systemImage: approvers.isEmpty ? "person.badge.shield.checkmark" : "checkmark.circle",
                iconColor: approvers.isEmpty ? c.tx2 : c.green,
                title: AnyView(title(approvers: approvers, youApproved: youApproved, left: left)),
                actions: [AnyView(Group {
                    if open && youApproved {
                        GitlabMrButton(label: appString("revokeApproval", "Revoke approval"), secondary: true, loading: busy == .unapprove,
                                       disabled: busy != nil, action: commands.unapprove)
                    } else if open && (entity.userCanApprove ?? true) {
                        GitlabMrButton(label: appString("approve", "Approve"), loading: busy == .approve, disabled: busy != nil, action: commands.approve)
                    }
                })])
        }
    }

    @ViewBuilder private func title(approvers: [String], youApproved: Bool, left: Int) -> some View {
        if approvers.isEmpty {
            Text(left > 0 ? approvalsLeftText(left) : appString("approvalOptional", "Approval is optional"))
        } else if youApproved && approvers.count == 1 {
            Text(appString("approvedByYou", "Approved by you"))
        } else {
            FlowLayout(spacing: theme.spacing.s6, rowSpacing: theme.spacing.s4) {
                Text(appString("approvedByLabel", "Approved by"))
                ForEach(approvers, id: \.self) { name in
                    ProviderAvatarImage(name: name, avatarUrl: entity.userAvatarUrls[name], imageLoader: avatarLoader).help(name)
                }
            }
        }
    }

    private func approvalsLeftText(_ n: Int) -> String {
        n == 1 ? appString("approvalsLeftOne", "Requires 1 more approval") : appFormat("approvalsLeftOther", "Requires %1$@ more approvals", "\(n)")
    }
}
