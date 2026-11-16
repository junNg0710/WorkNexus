/// Ported from: lib/tools/zentao/presentation/detail/bug_attachments.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The attachments section: repro videos, screenshots and logs. A tap opens the in-app viewer.
public struct ZentaoBugAttachments: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let ticket: Ticket; let attachments: [TicketAttachment]
    @State private var viewing: TicketAttachment?

    public init(deps: ZentaoDependencies, ticket: Ticket, attachments: [TicketAttachment]) {
        self.deps = deps; self.ticket = ticket; self.attachments = attachments
    }

    public var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                SectionLabel("\(appString("attachments", "Attachments")) · \(attachments.count)")
                ForEach(attachments) { a in ZentaoAttachmentRow(attachment: a) { viewing = a } }
            }
            .appDialog(item: $viewing) { a in ZentaoAttachmentViewer(deps: deps, ticket: ticket, attachment: a) { viewing = nil } }
        }
    }
}

private struct ZentaoAttachmentRow: View {
    @Environment(\.appTheme) private var theme
    let attachment: TicketAttachment; let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        let subtitle = [formatFileSize(attachment.size), attachment.addedBy.flatMap { $0.isEmpty ? nil : $0 }].compactMap { $0 }.joined(separator: " · ")
        HoverSurface(onTap: onTap, fill: c.panel2, border: c.line, cornerRadius: theme.radii.md) {
            HStack(spacing: theme.spacing.s10) {
                Image(systemName: ZentaoFileKinds.icon(of: attachment)).font(.system(size: theme.sizes.icon16)).foregroundStyle(c.accent)
                    .frame(width: theme.sizes.control32, height: theme.sizes.control32)
                    .background(c.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: theme.radii.md))
                VStack(alignment: .leading, spacing: theme.spacing.s2) {
                    Text(attachment.title).font(theme.typography.meta).foregroundStyle(c.tx).lineLimit(1)
                    if !subtitle.isEmpty { Text(subtitle).font(theme.typography.caption).foregroundStyle(c.tx3) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: ZentaoFileKinds.isViewable(attachment) ? "eye" : "arrow.down.circle")
                    .font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx3)
                    .frame(width: theme.sizes.control32, height: theme.sizes.control32)
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.line, lineWidth: theme.borders.hairline))
            }
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
        }
    }
}
