import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{assign_dialog,reviewers_dialog}.dart
/// Assigns a GitLab item to one provider user (with an optional note) or sets a PR's reviewers: the user picker in a
/// dialog frame; Save runs the service call, reports a toast and closes.
struct GitlabAssignDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let ctx: GitlabContext
    let ticket: Ticket
    let multiple: Bool
    let onClose: () -> Void
    @State private var note = ""

    var body: some View {
        let service = ctx.mrService, t = ticket
        let loader: AvatarLoader = { url in await service.fetchTicketImage(t, url: url) }
        let title = appFormat("zentaoActionTitle", "%1$@ #%2$@", multiple ? appString("reviewers", "Reviewers") : appString("assign", "Assign"), ticket.externalKey)
        AppDialogFrame(title: title, leadingIcon: multiple ? "square.and.pencil" : "person.badge.plus", onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                if !multiple {
                    Text(appString("zentaoNote", "Note")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                    TextField("", text: $note, axis: .vertical).lineLimit(2...4).textFieldStyle(.plain).font(theme.typography.body)
                        .padding(theme.spacing.s10).background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.md))
                        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line2, lineWidth: theme.borders.hairline))
                }
                GitlabUserPickerEditor(currentUsers: current, multiple: multiple, loadUsers: { await service.listUsers(t) },
                                       onSave: save, onClose: onClose, avatarLoader: loader, width: nil)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        }
    }

    private var current: [String] {
        guard case .gitlabItem(let g)? = ticket.providerEntity else { return [ticket.assignee].compactMap { $0 } }
        return multiple ? g.reviewers : (g.assignees.isEmpty ? [ticket.assignee].compactMap { $0 } : g.assignees)
    }

    private func save(_ accounts: [String]) async -> Outcome<Void> {
        let res: Outcome<Void>
        if multiple { res = await ctx.mrService.setReviewers(ticket, logins: accounts) }
        else {
            let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
            res = await ctx.mrService.assignTicket(ticket, assignee: accounts.first ?? "", comment: text.isEmpty ? nil : text)
        }
        if case .success = res {
            toasts?.show(multiple ? appString("reviewersUpdated", "Reviewers updated")
                                  : appFormat("taskDetailAssignedTo", "Assigned to %1$@", accounts.first ?? ""))
        }
        return res
    }
}
