import CoreDomain
import CoreTools
import CoreUI
import FeatureChat
import Foundation
import SharedKit

/// Ported from: lib/features/chat/presentation/widgets/ticket_link_handler.dart + chat_links.dart (`openChatLink`).
/// Makes a ZenTao bug / task / story link tapped anywhere in the app (a description, a comment, a notification, the chat) open
/// in the ticket detail panel instead of a mini app or the browser: a ticket the board already synced opens at once, any
/// other is fetched from ZenTao first, and one that cannot be loaded falls back to the browser. Links to anything else pass
/// through to the next stages of the `LinkRouter` (`LinkStage.app`).
@MainActor
final class TicketLinkHandler: LinkHandler {
    private let shell: ShellModel
    private let router: LinkRouter

    init(shell: ShellModel, router: LinkRouter = .shared) {
        self.shell = shell; self.router = router
        router.register(.app, self)
    }

    func handle(_ url: String) -> Bool {
        guard let link = FindLinkedTicket.parse(url) else { return false }
        if let known = FindLinkedTicket()(url, Array(shell.detail.tickets.values)) {
            shell.nav.openTicket(known.id)
            return true
        }
        guard let fetch = shell.services.zentaoTickets else { return false }
        Task { @MainActor [shell] in
            if case .success(let id) = await fetch.fetchZenTaoTicket(host: link.host, type: link.type, id: link.id) {
                shell.nav.openTicket(id)
            } else {
                _ = openExternally(url)
            }
        }
        return true
    }
}
