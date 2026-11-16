/// Ported from: lib/features/chat/presentation/widgets/notification_body.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A ZenTao / xuanbot notification: who it is from and the project on one line, the title, then the item — as a live
/// ticket card (status, priority, assignee) when it is a ZenTao bug / task / story, else its Markdown text, then "View
/// details" (only without a card, which opens the item itself) and its other actions.
struct NotificationBodyView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let ctx: ThreadContext
    let notification: NotificationContent

    private static let leadingId = RX(#"^#\d+\s*"#)

    var body: some View {
        let n = notification
        let subtitle = n.subtitle != n.title ? n.subtitle : nil
        // The card already says what the text would (and keeps it current).
        let ticketUrl = n.url.flatMap { FindLinkedTicket.parse($0) != nil ? $0 : nil }
        let meta = [n.sender, subtitle].compactMap { $0 }.joined(separator: " · ")
        let links = detailLinks(n, ticketUrl)
        VStack(alignment: .leading, spacing: 0) {
            if !meta.isEmpty { Text(meta).font(theme.typography.caption).foregroundStyle(ink.meta.color) }
            if let title = n.title {
                Text(title).font(theme.typography.font(size: ink.fontSize, weight: .semibold)).foregroundStyle(ink.text.color)
                    .padding(.top, meta.isEmpty ? 0 : theme.spacing.s2)
            }
            if let ticketUrl {
                TicketLinkCard(ctx: ctx, url: ticketUrl, fallbackTitle: n.text.isEmpty ? nil : Self.leadingId.replace(n.text) { _ in "" })
            } else if !n.text.isEmpty {
                // A notice is rendered as Markdown only when sent as such — not when plain text happens to look like it.
                ChatTextBody(ctx: ctx, text: n.text, markdown: n.markdown && hasMarkdownSyntax(n.text))
                    .padding(.top, n.title == nil ? 0 : theme.spacing.s6)
            }
            if !links.isEmpty {
                FlowLayout(spacing: theme.spacing.s8) {
                    ForEach(Array(links.enumerated()), id: \.offset) { i, link in
                        Button { ctx.openLink(link.url) } label: {
                            Label(link.label, systemImage: i == 0 && n.url != nil && ticketUrl == nil ? "arrow.right.circle" : "arrow.up.right.square")
                                .font(theme.typography.metaStrong).foregroundStyle(ink.link.color)
                        }
                        .buttonStyle(.plain).pointerStyle(.link)
                    }
                }
                .padding(.top, theme.spacing.s8)
            }
        }
    }

    private func detailLinks(_ n: NotificationContent, _ ticketUrl: String?) -> [(label: String, url: String)] {
        var out: [(label: String, url: String)] = []
        // The ticket card opens the item itself.
        if let url = n.url, ticketUrl == nil { out.append((appString("chatViewDetail", "View details"), url)) }
        for a in n.actions where a.url != n.url { out.append((a.label, a.url)) }
        return out
    }
}

/// Lays its children out in rows, wrapping at the available width (Flutter `Wrap`).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = arrange(bounds.width, subviews)
        for (i, p) in laid.points.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified) }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing; rowH = max(rowH, size.height); maxX = max(maxX, x - spacing)
        }
        return (points, CGSize(width: maxX, height: y + rowH))
    }
}
