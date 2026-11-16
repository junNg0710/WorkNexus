import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_mr_sidebar.dart
/// The GitLab MR metadata sidebar: editable Assignee, Reviewers (with approval checks), Labels, Milestone and Time
/// tracking — each editor opens as a popover — plus a participants roll-up as a row of avatars.
struct GitlabMrSidebar: View {
    @Environment(\.appTheme) private var theme
    let ctx: GitlabContext
    let ticket: Ticket
    let entity: GitLabItemEntity

    private var assignees: [String] {
        entity.assignees.isEmpty ? [ticket.assignee].compactMap { $0 }.filter { !$0.isEmpty } : entity.assignees
    }

    private var participants: [String] {
        var seen = Set<String>(), out: [String] = []
        for n in [entity.author ?? ""] + entity.assignees + entity.reviewers where !n.isEmpty && seen.insert(n).inserted { out.append(n) }
        return out
    }

    private var avatarUrls: [String: String] {
        var urls = entity.userAvatarUrls
        if let a = entity.author, !a.isEmpty, let u = entity.authorAvatarUrl, !u.isEmpty { urls[a] = u }
        return urls
    }

    private var timeSummary: String {
        var parts: [String] = []
        if let e = entity.humanTimeEstimate, !e.isEmpty { parts.append(appFormat("estimateSummary", "Estimate %1$@", e)) }
        if let s = entity.humanTotalTimeSpent, !s.isEmpty { parts.append(appFormat("spentSummary", "Spent %1$@", s)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let service = ctx.mrService, t = ticket
        let loader: AvatarLoader = { url in await service.fetchTicketImage(t, url: url) }
        let labels = visibleUserLabels(ticket.labels)
        let edit = appString("edit", "Edit")
        VStack(alignment: .leading, spacing: 0) {
            GitlabSidebarSection(title: appString("assignee", "Assignee"), action: edit, editor: { close in
                AnyView(GitlabUserPickerEditor(
                    currentUsers: assignees, multiple: false, loadUsers: { await service.listUsers(t) },
                    onSave: { accounts in await service.assignTicket(t, assignee: accounts.first ?? "", comment: nil) },
                    onClose: close, avatarLoader: loader))
            }) {
                if assignees.isEmpty { GitlabMutedText(appString("none", "None")) } else { GitlabNameList(names: assignees, avatarUrls: avatarUrls, loader: loader) }
            }
            GitlabSidebarSection(title: reviewersTitle, action: edit, editor: { close in
                AnyView(GitlabUserPickerEditor(
                    currentUsers: entity.reviewers, multiple: true, loadUsers: { await service.listUsers(t) },
                    onSave: { accounts in await service.setReviewers(t, logins: accounts) },
                    onClose: close, avatarLoader: loader))
            }) {
                if entity.reviewers.isEmpty { GitlabMutedText(appString("noReviewersAssignYourself", "None - assign yourself")) }
                else { GitlabNameList(names: entity.reviewers, avatarUrls: avatarUrls, loader: loader, approved: Set(entity.approvedBy)) }
            }
            GitlabSidebarSection(title: appString("labels", "Labels"), action: edit, editor: { close in
                AnyView(GitlabLabelsEditor(currentLabels: labels, loadOptions: { await service.listGitLabLabels(t) },
                                           onSave: { await service.setGitLabLabels(t, labels: $0) }, onClose: close))
            }) {
                if labels.isEmpty { GitlabMutedText(appString("none", "None")) } else { LabelChips(labels, colors: entity.labelColors, textColors: entity.labelTextColors) }
            }
            GitlabSidebarSection(title: appString("milestone", "Milestone"), action: edit, editor: { close in
                AnyView(GitlabMilestoneEditor(currentMilestoneId: entity.milestoneId, loadOptions: { await service.listGitLabMilestones(t) },
                                              onSave: { await service.setGitLabMilestone(t, milestoneId: $0) }, onClose: close))
            }) { GitlabMutedText(entity.milestoneTitle ?? appString("none", "None")) }
            GitlabSidebarSection(title: appString("timeTracking", "Time tracking"), trailingIcon: "plus",
                                 actionTooltip: appString("editTimeTracking", "Edit time tracking"), editor: { close in
                AnyView(GitlabTimeTrackingEditor(
                    currentEstimate: entity.humanTimeEstimate, currentSpent: entity.humanTotalTimeSpent,
                    onSave: { estimate, spent, resetEstimate, resetSpent in
                        await service.updateGitLabTimeTracking(t, estimate: estimate, spent: spent, resetEstimate: resetEstimate, resetSpent: resetSpent)
                    }, onClose: close))
            }) { GitlabMutedText(timeSummary.isEmpty ? appString("noEstimateOrTimeSpent", "No estimate or time spent") : timeSummary) }
            GitlabSidebarSection(title: "\(participants.count) \(participants.count == 1 ? appString("participant", "Participant") : appString("participants", "Participants"))") {
                if participants.isEmpty { GitlabMutedText(appString("none", "None")) } else {
                    FlowLayout(spacing: theme.spacing.s6, rowSpacing: theme.spacing.s6) {
                        ForEach(participants, id: \.self) { ProviderAvatarImage(name: $0, avatarUrl: avatarUrls[$0], imageLoader: loader).help($0) }
                    }
                }
            }
        }
    }

    private var reviewersTitle: String {
        entity.reviewers.count == 1 ? appString("reviewerSingular", "Reviewer") : appString("reviewers", "Reviewers")
    }
}

/// People as avatar + name rows; `approved` names carry an approval check.
struct GitlabNameList: View {
    @Environment(\.appTheme) private var theme
    let names: [String]; let avatarUrls: [String: String]; let loader: AvatarLoader
    var approved: Set<String> = []
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            ForEach(names, id: \.self) { name in
                ProviderUserAvatar(name: name, avatarUrl: avatarUrls[name], imageLoader: loader) {
                    if approved.contains(name) {
                        Image(systemName: "checkmark.circle").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.green)
                            .help(appString("reviewerApproved", "Approved"))
                    }
                }
            }
        }
    }
}
