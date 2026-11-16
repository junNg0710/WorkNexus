import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{comments_section,detail_activity_timeline}.dart
/// Comments and activity merged into one chronological timeline (provider comments only — internal notes stay out),
/// with the composer under it.
public struct CommentsSection: View {
    @Environment(\.appTheme) private var theme
    let controller: DetailController; let ticket: Ticket; let model: TicketDetailModel; let images: BodyImageHooks

    public init(controller: DetailController, ticket: Ticket, model: TicketDetailModel, images: BodyImageHooks) {
        self.controller = controller; self.ticket = ticket; self.model = model; self.images = images
    }

    private enum Entry: Identifiable {
        case comment(Comment), event(ActivityEvent)
        var at: Date { switch self { case .comment(let c): c.createdAt; case .event(let e): e.at } }
        var id: String { switch self { case .comment(let c): "c\(c.id)"; case .event(let e): "e\(e.id)" } }
    }

    private var entries: [Entry] {
        let all = model.comments.filter { $0.origin == .provider }.map(Entry.comment)
            + model.activity.filter { $0.action != "commented" }.map(Entry.event)
        return all.enumerated().sorted { a, b in a.element.at != b.element.at ? a.element.at < b.element.at : a.offset < b.offset }.map(\.element)
    }

    private var files: [TicketAttachment] {
        if case .zentaoBug(let b)? = ticket.providerEntity { return b.attachments }
        return []
    }

    public var body: some View {
        let items = entries
        let df = controller.settings.dateFormat
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            if items.isEmpty {
                Text(appString("noActivityYet", "No activity yet")).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx3)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    switch item {
                    case .comment(let c):
                        CommentTile(c, html: isHtmlBody(ticket.providerType, c.body), isFirst: i == 0, isLast: i == items.count - 1,
                                    images: images, dateFormat: df)
                    case .event(let e):
                        ActivityRow(e, isFirst: i == 0, isLast: i == items.count - 1, files: files,
                                    onOpenFile: { f in controller.openAttachment(ticket, f) }, dateFormat: df,
                                    loadStill: { f in await controller.attachmentThumbnail(ticket, f) })
                    }
                }
            }
            .textSelection(.enabled)
            CommentComposer(controller: controller, ticket: ticket, model: model).padding(.top, theme.spacing.s8)
        }
    }
}

/// A standalone activity timeline with a plain composer and optional Close / Reopen buttons (the Git providers' MR / issue
/// panels); `onComment` returns whether the comment was posted.
public struct DetailActivityTimeline: View {
    @Environment(\.appTheme) private var theme
    let comments: [Comment]; let activity: [ActivityEvent]
    let onComment: (String) async -> Bool; let onCloseItem: () -> Void; let canClose: Bool; var onReopenItem: (() -> Void)?
    @State private var text = ""
    @State private var posting = false

    public init(comments: [Comment], activity: [ActivityEvent], onComment: @escaping (String) async -> Bool,
                onCloseItem: @escaping () -> Void, canClose: Bool, onReopenItem: (() -> Void)? = nil) {
        self.comments = comments; self.activity = activity; self.onComment = onComment
        self.onCloseItem = onCloseItem; self.canClose = canClose; self.onReopenItem = onReopenItem
    }

    private enum Entry { case comment(Comment), event(ActivityEvent) }

    public var body: some View {
        let c = theme.colors
        let entries: [(Date, Entry)] = (comments.map { ($0.createdAt, Entry.comment($0)) }
            + activity.filter { $0.action != "commented" }.map { ($0.at, Entry.event($0)) }).sorted { $0.0 < $1.0 }
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            DetailSectionTitle(appString("activity", "Activity"))
            if entries.isEmpty {
                Text(appString("noActivityYet", "No activity yet")).font(theme.typography.paragraph).foregroundStyle(c.tx3)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { i, e in
                switch e.1 {
                case .comment(let cm): CommentTile(cm, isFirst: i == 0, isLast: i == entries.count - 1)
                case .event(let ev): ActivityRow(ev, isFirst: i == 0, isLast: i == entries.count - 1)
                }
            }
            TextField(appString("writeCommentHint", "Write a comment…"), text: $text, axis: .vertical).lineLimit(4...8)
                .textFieldStyle(.plain).font(theme.typography.body).padding(theme.spacing.s12)
                .background(c.card, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.line2, lineWidth: theme.borders.hairline))
                .padding(.top, theme.spacing.s14)
            HStack(spacing: theme.spacing.s8) {
                AppButton(appString("commentAction", "Comment"), kind: .primary) {
                    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !body.isEmpty, !posting else { return }
                    posting = true
                    Task { if await onComment(body) { text = "" }; posting = false }
                }
                .disabled(posting)
                if canClose { AppButton(appString("close", "Close"), kind: .secondary, action: onCloseItem) }
                if let onReopenItem { AppButton(appString("gitlabReopen", "Reopen"), kind: .secondary, action: onReopenItem) }
            }
        }
    }
}
