import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/github/presentation/detail/github_pr_sidebar.dart
/// The GitHub PR metadata sidebar: editable Assignee + Reviewers (what GitHub's PAT API supports), read-only Labels
/// (no label API through a PAT) and a participants roll-up. Milestone / time tracking are absent — GitHub exposes no
/// PAT endpoint for them.
struct GithubPrSidebar: View {
    let ctx: GithubContext
    let ticket: Ticket
    let entity: GitHubItemEntity

    private var assignees: [String] {
        entity.assignees.isEmpty ? [ticket.assignee].compactMap { $0 }.filter { !$0.isEmpty } : entity.assignees
    }

    private var participants: [String] {
        var seen = Set<String>(), out: [String] = []
        for n in [entity.author ?? ""] + entity.assignees + entity.reviewers where !n.isEmpty && seen.insert(n).inserted { out.append(n) }
        return out
    }

    var body: some View {
        let service = ctx.prService, t = ticket
        let loader: AvatarLoader = { url in await service.fetchTicketImage(t, url: url) }
        let labels = visibleUserLabels(ticket.labels)
        let avatars = [entity.author ?? "": entity.authorAvatarUrl ?? ""].filter { !$0.key.isEmpty && !$0.value.isEmpty }
        VStack(alignment: .leading, spacing: 0) {
            GithubSidebarSection(title: appString("assignee", "Assignee"), action: appString("edit", "Edit"), editor: { close in
                AnyView(GithubUserPickerEditor(
                    currentUsers: assignees, multiple: false, loadUsers: { await service.listUsers(t) },
                    onSave: { accounts in await service.assignTicket(t, assignee: accounts.first ?? "", comment: nil) },
                    onClose: close, avatarLoader: loader))
            }) {
                if assignees.isEmpty { GithubMutedText(appString("none", "None")) } else { GithubNameList(names: assignees, avatarUrls: avatars, loader: loader) }
            }
            GithubSidebarSection(title: appString("reviewers", "Reviewers"), action: appString("edit", "Edit"), editor: { close in
                AnyView(GithubUserPickerEditor(
                    currentUsers: entity.reviewers, multiple: true, loadUsers: { await service.listUsers(t) },
                    onSave: { accounts in await service.setReviewers(t, logins: accounts) },
                    onClose: close, avatarLoader: loader))
            }) {
                if entity.reviewers.isEmpty { GithubMutedText(appString("noReviewersAssignYourself", "None - assign yourself")) }
                else { GithubNameList(names: entity.reviewers, avatarUrls: avatars, loader: loader) }
            }
            GithubSidebarSection(title: appString("labels", "Labels")) {
                if labels.isEmpty { GithubMutedText(appString("none", "None")) } else { LabelChips(labels) }
            }
            GithubSidebarSection(title: "\(participants.count) \(participants.count == 1 ? appString("participant", "Participant") : appString("participants", "Participants"))") {
                if participants.isEmpty { GithubMutedText(appString("none", "None")) } else { GithubNameList(names: participants, avatarUrls: avatars, loader: loader) }
            }
        }
    }
}

/// People as avatar + name rows.
struct GithubNameList: View {
    @Environment(\.appTheme) private var theme
    let names: [String]; let avatarUrls: [String: String]; let loader: AvatarLoader
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            ForEach(names, id: \.self) { ProviderUserAvatar(name: $0, avatarUrl: avatarUrls[$0], imageLoader: loader) }
        }
    }
}
