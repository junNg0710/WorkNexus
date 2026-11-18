import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{detail_header,detail_header_top_bar,detail_header_title,detail_back_button,
/// detail_header_more_button}.dart
/// Top of the detail panel: breadcrumb (workspace / ref) with back, edit, copy-link, open-in-browser, more and close; the title;
/// the people (assigned to / opened by) and the tool's action buttons; the tool's header extras above the title.
public struct DetailHeader: View {
    @Environment(\.appTheme) private var theme
    let controller: DetailController; let ticket: Ticket; let wsColor: Color; let model: TicketDetailModel; let onClose: () -> Void

    public init(controller: DetailController, ticket: Ticket, wsColor: Color, model: TicketDetailModel, onClose: @escaping () -> Void) {
        self.controller = controller; self.ticket = ticket; self.wsColor = wsColor; self.model = model; self.onClose = onClose
    }

    public var body: some View {
        let s = theme.spacing
        let tool = controller.registry.module(for: ticket.providerType)
        VStack(alignment: .leading, spacing: s.s12) {
            DetailHeaderTopBar(controller: controller, ticket: ticket, wsColor: wsColor, model: model, onClose: onClose)
            if let extras = tool?.buildDetailHeaderExtras(ticket: ticket) { extras }
            DetailHeaderTitle(ticket: ticket)
            HStack(alignment: .bottom, spacing: s.s20) {
                DetailPeople(ticket: ticket)
                Spacer(minLength: 0)
                if let actions = tool?.buildActions(ticket: ticket) { actions }
            }
        }
        .padding(EdgeInsets(top: s.s14, leading: s.s24, bottom: s.s16, trailing: s.s24))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}

struct DetailHeaderTopBar: View {
    @Environment(\.appTheme) private var theme
    let controller: DetailController; let ticket: Ticket; let wsColor: Color; let model: TicketDetailModel; let onClose: () -> Void
    @State private var sharing = false

    var body: some View {
        let c = theme.colors
        let ws = controller.workspace(of: ticket)
        let url = ticket.url ?? ""
        let canGoBack = (controller.nav.state.ticketHistories[controller.nav.state.rail.key]?.count ?? 0) > 1
        HStack(spacing: theme.spacing.s8) {
            if canGoBack { AppIconButton("arrow.left", help: appString("back", "Back")) { controller.nav.goBackTicket() } }
            WorkspaceBadge(wsColor, ws?.shortCode ?? "?", iconKey: ws?.iconKey)
            Text(ws?.isPersonal == true ? appString("personal", "Personal") : (ws?.name ?? "")).font(theme.typography.meta)
                .foregroundStyle(c.tx2).lineLimit(1)
            Text("/").font(theme.typography.meta).foregroundStyle(c.tx3)
            Text(ticketRef(ticket.providerType, ticket.externalKey, ticket.externalType)).font(theme.typography.mono).foregroundStyle(c.tx3)
            Spacer(minLength: theme.spacing.s8)
            if let route = controller.extensions.route(for: ticket) {
                AppIconButton("pencil", help: appString("edit", "Edit"), outlined: true) { controller.nav.openEditor(route) }
            }
            if !url.isEmpty {
                // Its own button, as on a merge request's header: the link is what gets pasted into chat all day.
                CopyLinkButton(url: url)
                if let share = controller.extensions.shareToChat {
                    // Pass the ticket on in chat without leaving it: pick the chats, it sends "#12 Title" and the link.
                    AppIconButton("paperplane", help: appString("shareInChat", "Share in chat"), outlined: true) { sharing = true }
                        .appDialog(isPresented: $sharing) { share(ticket) { sharing = false } }
                }
                AppIconButton("arrow.up.right.square", help: appString("openInBrowser", "Open in browser"), outlined: true) {
                    if let open = controller.extensions.openLink { open(url) } else { openLinkExternally(url, inApp: false) }
                }
            }
            DetailHeaderMoreButton(ticket: ticket, model: model)
            AppIconButton("xmark", help: appString("close", "Close"), outlined: true, action: onClose)
        }
    }
}

struct DetailHeaderMoreButton: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let ticket: Ticket; let model: TicketDetailModel

    private func copy(_ text: String, _ done: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        toasts?.show(done)
    }

    /// A button like its neighbours (the whole square takes the click; a SwiftUI menu took it only on the dots), opening a
    /// native menu under the pointer.
    var body: some View {
        AppIconButton("ellipsis", help: appString("more", "More"), outlined: true) {
            AppNativeMenu.popUp([
                AppNativeMenu.Item(appString("refresh", "Refresh"), icon: "arrow.triangle.2.circlepath") { model.refresh(ticket) },
                AppNativeMenu.Item(appString("copyTitle", "Copy title"), icon: "doc.on.doc") {
                    copy(ticketTitleWithRef(ticket), appString("titleCopied", "Title copied"))
                },
            ])
        }
    }
}

/// "#12 Title" with the ref in the muted tone; selectable.
struct DetailHeaderTitle: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        (Text(ticketShortRef(ticket.providerType, ticket.externalKey)).foregroundColor(theme.colors.tx3) + Text(" \(ticket.title)").foregroundColor(theme.colors.tx))
            .font(theme.typography.title).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Assigned to / opened by.
struct DetailPeople: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.personChip) private var chip
    let ticket: Ticket
    private static let avatar: CGFloat = 24

    var body: some View {
        let (assignee, reporter): (String, String) = switch ticket.providerEntity {
        case .zentaoBug(let b)?: (b.assignedTo ?? ticket.assignee ?? "", b.openedBy ?? "")
        case .zentaoTask(let t)?: (ticket.assignee ?? "", t.openedBy ?? "")
        case .gitlabItem(let g)?: (ticket.assignee ?? "", g.author ?? "")
        default: (ticket.assignee ?? "", "")
        }
        HStack(alignment: .top, spacing: theme.spacing.s20) {
            PersonField(label: appString("assignedTo", "Assigned to"), name: assignee.trimmingCharacters(in: .whitespaces), ticket: ticket, chip: chip)
            if !reporter.trimmingCharacters(in: .whitespaces).isEmpty {
                PersonField(label: appString("openedBy", "Opened by"), name: reporter.trimmingCharacters(in: .whitespaces), ticket: ticket, chip: chip)
            }
        }
    }
}

private struct PersonField: View {
    @Environment(\.appTheme) private var theme
    let label: String; let name: String; let ticket: Ticket; let chip: ((PersonAvatarRequest) -> AnyView)?
    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            Text(label).font(theme.typography.caption).foregroundStyle(c.tx3)
            if name.isEmpty {
                Text(appString("unassigned", "Unassigned")).font(theme.typography.paragraph).foregroundStyle(c.tx3)
            } else if ticket.providerType == .zentao, let chip {
                chip(PersonAvatarRequest(accountId: ticket.accountId, name: name, diameter: 24))
            } else {
                HStack(spacing: theme.spacing.s6) {
                    UserAvatar(name: name, size: 24)
                    Text(name).font(theme.typography.paragraph).foregroundStyle(c.tx)
                }
            }
        }
    }
}
