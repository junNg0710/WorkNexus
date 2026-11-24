/// Ported from: lib/features/chat/presentation/widgets/message_link_previews.dart
import CoreDomain
import SwiftUI

/// In a message's bubble, under its text: a compact live card for each merge request, GitLab/GitHub issue and ZenTao
/// ticket it links (a few at most), then a preview of the first other web page. The links themselves stay in the text.
struct MessageLinkPreviews: View {
    let ctx: ThreadContext
    let message: ChatMessage

    /// Most live link cards (MRs, ZenTao tickets) one message shows.
    static let maxLinkCards = 4

    /// Links shown as a live card rather than a page preview.
    static func isCardLink(_ url: String) -> Bool {
        ParseMergeRequestLink()(url) != nil || FindLinkedTicket.parse(url) != nil
    }

    /// The web addresses a message's previews are for: those in its text, or the shared link itself.
    static func previewUrls(_ message: ChatMessage) -> [String] {
        if message.deleted { return [] }
        switch message.content {
        // Asked for every text message on every redraw of its row: no address without "://".
        case .text(let t, _): return t.contains("://") ? ChatTextLabels.urls(t) : []
        case .link(let url, _): return [url]
        default: return []
        }
    }

    /// Whether `message` shows link cards or a page preview under its text.
    static func hasPreviews(_ message: ChatMessage) -> Bool { !previewUrls(message).isEmpty }

    var body: some View {
        let urls = Self.previewUrls(message)
        if !urls.isEmpty {
            let cards = Array(urls.filter(Self.isCardLink).prefix(Self.maxLinkCards))
            let page = urls.first { !Self.isCardLink($0) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(cards, id: \.self) { TicketLinkCard(ctx: ctx, url: $0) }
                if let page { LinkPreviewCard(ctx: ctx, url: page) }
            }
        }
    }
}
