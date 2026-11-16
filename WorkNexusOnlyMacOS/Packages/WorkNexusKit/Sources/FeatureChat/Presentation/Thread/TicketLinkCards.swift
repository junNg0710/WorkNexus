/// Ported from: lib/features/chat/presentation/widgets/zentao_ticket_card.dart + merge_request_card.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// A ZenTao bug / task / story, a GitLab merge request / issue or a GitHub pull request / issue linked in a message, as
/// a compact quote-like card with its live state: `Bug #123 · Status`, the title, then `Pri 2 · assignee` (for a merge
/// request `author · +lines −lines · files`). The bar takes the state's colour. Looked up through the app's ticket
/// repository (`ChatServices.ticketLookup`); a tap opens the item beside the chat.
struct TicketLinkCard: View {
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let url: String
    /// Shown until the ticket is loaded, or when it cannot be (a bot notification already names the item).
    var fallbackTitle: String?
    @State private var ticket: Ticket?
    @State private var loading = true
    /// Why the provider could not be asked or answered; nil while fine.
    @State private var failure: CoreDomain.Failure?
    @MainActor private static var freshness = MergeRequestFreshness()

    var body: some View {
        let mr = ParseMergeRequestLink()(url)
        let zt = FindLinkedTicket.parse(url)
        if mr != nil || zt != nil {
            let tint = ticket.map { TicketCardStyle.stateColor($0, theme: theme.colors) }
            ChatLinkCardFrame(onTap: tap, bar: tint?.color) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: theme.spacing.s6) {
                        BrandLogoBadge(mr?.provider ?? .zentao, size: 14)
                        ChatCardLine(parts: headParts(mr, zt, tint))
                    }
                    if let ticket {
                        ChatCardTitle(title: ticket.title)
                        ChatCardLine(parts: footParts(ticket, mr))
                    } else {
                        if let fallbackTitle { ChatCardTitle(title: fallbackTitle) }
                        if !loading || mr != nil { ChatCardLine(parts: [.plain(note(mr, zt))]) }
                    }
                }
            }
            .task(id: url) { await load(resumed: false) }
            // Coming back to the app refetches one still open, so a merge done in the browser shows at once.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard mr != nil, !MergeRequestFreshness.isFinal(ticket) else { return }
                Task { await load(resumed: true) }
            }
        }
    }

    /// The stored item first, then (for a GitLab/GitHub link) the provider's current state.
    private func load(resumed: Bool) async {
        if ticket == nil { loading = true }
        if ticket == nil { ticket = await ctx.services.ticketLookup?(url) }
        guard let link = ParseMergeRequestLink()(url), let service = ctx.services.mergeRequests,
              Self.freshness.needsFetch(url, stored: ticket, resumed: resumed) else { loading = false; return }
        loading = ticket == nil
        switch await service.fetchMergeRequest(link) {
        case .success(let fetched): ticket = fetched; failure = nil; Self.freshness.fetched(url)
        case .failure(let f): if ticket == nil { failure = f }
        }
        loading = false
    }

    private func tap() {
        if let ticket, let open = ctx.services.openTicket { open(ticket) } else { ctx.openLink(url) }
    }

    private func headParts(_ mr: MergeRequestLink?, _ zt: (type: String, id: String, host: String)?, _ tint: ChatColor?) -> [ChatCardPart] {
        if let mr {
            var parts: [ChatCardPart] = []
            if let ticket, let tint { parts.append(.strong(TicketCardStyle.mergeLabel(ticket), tint)) }
            parts.append(.plain(Self.reference(mr)))
            if let updated = ticket?.updatedAt { parts.append(.plain(ChatTextLabels.ago(updated))) }
            return parts
        }
        guard let zt else { return [] }
        var parts: [ChatCardPart] = [.plain("\(zt.type.prefix(1).uppercased())\(zt.type.dropFirst()) #\(zt.id)")]
        if let ticket, let tint { parts.append(.strong(TicketCardStyle.statusLabel(ticket.status), tint)) }
        return parts
    }

    private func footParts(_ t: Ticket, _ mr: MergeRequestLink?) -> [ChatCardPart] {
        if mr == nil {
            var parts: [ChatCardPart] = [.strong("Pri \(t.priority.level + 1)", TicketCardStyle.priorityColor(t.priority, theme: theme.colors))]
            if let a = t.assignee { parts.append(.plain(a)) }
            return parts
        }
        var author: String?, added: Int?, removed: Int?, files: Int?
        switch t.providerEntity {
        case .gitlabItem(let e): (author, added, removed, files) = (e.author, e.additions, e.deletions, e.changedFiles)
        case .githubItem(let e): (author, added, removed, files) = (e.author, e.additions, e.deletions, e.changedFiles)
        default: break
        }
        var parts: [ChatCardPart] = []
        if let author { parts.append(.plain(author)) }
        if let added, let removed {
            parts.append(.strong("+\(added.formatted())", ChatColor(theme.colors.green)))
            parts.append(.strong("−\(removed.formatted())", ChatColor(theme.colors.red)))
        }
        if let files { parts.append(.plain(L.mrFiles(files))) }
        return parts
    }

    /// Why there is no state yet: loading, no account for the host, or failed.
    private func note(_ mr: MergeRequestLink?, _ zt: (type: String, id: String, host: String)?) -> String {
        if loading { return L.mrLoading }
        if case .notFound? = failure { return L.mrNoAccount(mr?.host ?? zt?.host ?? "") }
        if ctx.services.ticketLookup == nil && ctx.services.mergeRequests == nil { return L.mrNoAccount(mr?.host ?? zt?.host ?? "") }
        return L.mrUnavailable
    }

    /// `group/repo !12` (a GitLab MR) or `owner/repo #12` (a GitHub PR, or an issue on either).
    static func reference(_ link: MergeRequestLink) -> String {
        let gitlabMr = link.provider == .gitlab && link.kind == .mergeRequest
        return "\(link.project) \(gitlabMr ? "!" : "#")\(link.number)"
    }
}

/// Colours and labels of a linked item's state.
enum TicketCardStyle {
    static func stateColor(_ t: Ticket, theme c: AppPalette) -> ChatColor {
        if t.providerType == .gitlab || t.providerType == .github {
            switch t.providerStatus.lowercased() {
            case "merged": return ChatColor(c.violet)
            case "closed": return ChatColor(c.red)
            default: return ChatColor(c.green)
            }
        }
        switch t.status {
        case .inbox: return ChatColor(c.tx3)
        case .todo: return ChatColor(c.accent)
        case .inprogress: return ChatColor(c.orange)
        case .review: return ChatColor(c.violet)
        case .blocked: return ChatColor(c.red)
        case .done: return ChatColor(c.green)
        }
    }

    static func priorityColor(_ p: Priority, theme c: AppPalette) -> ChatColor {
        switch p {
        case .urgent: ChatColor(c.red)
        case .high: ChatColor(c.orange)
        case .medium: ChatColor(c.amber)
        case .low: ChatColor(c.tx3)
        }
    }

    static func statusLabel(_ s: UnifiedStatus) -> String {
        switch s {
        case .inbox: appString("statusInbox", "Inbox")
        case .todo: appString("statusTodo", "To do")
        case .inprogress: appString("statusInProgress", "In progress")
        case .review: appString("statusReview", "Review")
        case .blocked: appString("statusBlocked", "Blocked")
        case .done: appString("statusDone", "Done")
        }
    }

    static func mergeLabel(_ t: Ticket) -> String {
        switch t.providerStatus.lowercased() {
        case "merged": appString("statusMerged", "Merged")
        case "closed": appString("statusClosed", "Closed")
        default: appString("statusOpen", "Open")
        }
    }
}
