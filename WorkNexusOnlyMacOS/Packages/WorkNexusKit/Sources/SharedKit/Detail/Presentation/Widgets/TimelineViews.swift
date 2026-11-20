import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{timeline_item,timeline_headline,comment_tile}.dart
public let kTimelineGutter: CGFloat = 24
/// How tall a comment or note shows before "Show more" (about five lines of body text).
let kNoteCollapsedHeight: CGFloat = 112

/// One entry of the timeline: a marker in the gutter, a vertical rail joining neighbours, and the content.
public struct TimelineItem<Marker: View, Content: View>: View {
    @Environment(\.appTheme) private var theme
    let isFirst: Bool; let isLast: Bool; let marker: Marker; let content: Content

    public init(isFirst: Bool, isLast: Bool, @ViewBuilder marker: () -> Marker, @ViewBuilder content: () -> Content) {
        self.isFirst = isFirst; self.isLast = isLast; self.marker = marker(); self.content = content()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s12) {
            marker.frame(width: kTimelineGutter, height: kTimelineGutter)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, isLast ? 0 : theme.spacing.s14)
        .background(alignment: .topLeading) {
            if !(isFirst && isLast) {
                GeometryReader { geo in
                    Rectangle().fill(theme.colors.line).frame(width: 1)
                        .frame(height: isLast ? kTimelineGutter / 2 : geo.size.height - (isFirst ? kTimelineGutter / 2 : 0),
                               alignment: .top)
                        .offset(x: kTimelineGutter / 2, y: isFirst ? kTimelineGutter / 2 : 0)
                }
            }
        }
    }
}

/// "<actor> <action> … <when>" line with the person bold, @mentions / assignees in the accent.
public struct TimelineHeadline: View {
    @Environment(\.appTheme) private var theme
    let actor: String; let action: String; let at: Date; var compact = false; var dateFormat = "iso"

    public init(actor: String, action: String, at: Date, compact: Bool = false, dateFormat: String = "iso") {
        self.actor = actor; self.action = action; self.at = at; self.compact = compact; self.dateFormat = dateFormat
    }

    private var line: Text {
        let c = theme.colors
        var t = Text(actor).font(compact ? theme.typography.paragraph : theme.typography.body).foregroundColor(c.tx).fontWeight(.medium) + Text(verbatim: " ")
        for p in activityActionParts(action) {
            switch p.kind {
            case .plain: t = t + Text(p.text).foregroundColor(c.tx2)
            case .user: t = t + Text(p.text).foregroundColor(c.accent).fontWeight(.medium)
            case .value: t = t + Text(p.text).foregroundColor(c.tx).fontWeight(.medium)
            }
        }
        return t.font(compact ? theme.typography.paragraph : theme.typography.body)
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s8) {
            line.frame(maxWidth: .infinity, alignment: .leading)
            Text(formatWhen(at, format: dateFormat)).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
        }
        .padding(.top, max((kTimelineGutter - (compact ? 13 : 14) * 1.4) / 2, 0))
    }
}

struct TimelineAvatar: View {
    let name: String
    var body: some View { UserAvatar(name: name, size: kTimelineGutter) }
}

struct TimelineEventIcon: View {
    @Environment(\.appTheme) private var theme
    let kind: ActivityKind
    var body: some View {
        let c = theme.colors
        let (icon, color): (String, Color) = switch kind {
        case .created: ("plus", c.tx2)
        case .assigned: ("person", c.tx2)
        case .edited: ("pencil", c.tx2)
        case .resolved: ("checkmark", c.green)
        case .merged: ("arrow.triangle.merge", c.violet)
        case .reopened: ("arrow.counterclockwise", c.amber)
        case .confirmed: ("checkmark.seal", c.accent)
        case .closed: ("xmark", c.tx2)
        case .other: ("circle.fill", c.tx3)
        }
        Image(systemName: icon).font(.system(size: kTimelineGutter * 0.4, weight: .semibold)).foregroundStyle(color)
            .frame(width: kTimelineGutter * 0.8, height: kTimelineGutter * 0.8)
            .background(c.card, in: Circle()).overlay(Circle().stroke(c.line, lineWidth: theme.borders.hairline))
    }
}

struct NoteCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s8).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

/// A provider comment as a timeline entry.
public struct CommentTile: View {
    @Environment(\.appTheme) private var theme
    let comment: Comment; var html = false; var isFirst = false; var isLast = false
    var images = BodyImageHooks(); var dateFormat = "iso"

    public init(_ comment: Comment, html: Bool = false, isFirst: Bool = false, isLast: Bool = false,
                images: BodyImageHooks = BodyImageHooks(), dateFormat: String = "iso") {
        self.comment = comment; self.html = html; self.isFirst = isFirst; self.isLast = isLast; self.images = images; self.dateFormat = dateFormat
    }

    public var body: some View {
        TimelineItem(isFirst: isFirst, isLast: isLast) { TimelineAvatar(name: comment.authorName) } content: {
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                TimelineHeadline(actor: comment.authorName, action: appString("commentedAction", "commented"), at: comment.createdAt, dateFormat: dateFormat)
                NoteCard { CollapsibleBlock(collapsedHeight: kNoteCollapsedHeight) { RichBodyText(comment.body, html: html, height: 1.55, images: images) } }
            }
        }
    }
}

/// An activity event (assigned, resolved, …) as a timeline entry, with its note and attached files.
public struct ActivityRow: View {
    @Environment(\.appTheme) private var theme
    let event: ActivityEvent; var isFirst = false; var isLast = false
    var files: [TicketAttachment] = []; var onOpenFile: ((TicketAttachment) -> Void)?; var dateFormat = "iso"
    /// A still of an attached video (image bytes), shown on its frame card; nil: a plain chip.
    var loadStill: ((TicketAttachment) async -> Data?)?

    public init(_ event: ActivityEvent, isFirst: Bool = false, isLast: Bool = false, files: [TicketAttachment] = [],
                onOpenFile: ((TicketAttachment) -> Void)? = nil, dateFormat: String = "iso",
                loadStill: ((TicketAttachment) async -> Data?)? = nil) {
        self.event = event; self.isFirst = isFirst; self.isLast = isLast; self.files = files; self.onOpenFile = onOpenFile; self.dateFormat = dateFormat
        self.loadStill = loadStill
    }

    private func file(named name: String) -> TicketAttachment? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return files.first { $0.title.trimmingCharacters(in: .whitespaces).lowercased() == key }
    }

    public var body: some View {
        let note = event.detail ?? ""
        TimelineItem(isFirst: isFirst, isLast: isLast) { TimelineEventIcon(kind: activityKindOf(event.action)) } content: {
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                TimelineHeadline(actor: event.actor, action: event.action, at: event.at, compact: true, dateFormat: dateFormat)
                if !note.isEmpty {
                    NoteCard {
                        CollapsibleBlock(collapsedHeight: kNoteCollapsedHeight) {
                            Text(note).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineSpacing(4).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if !event.attachments.isEmpty {
                    FlowLayout(spacing: theme.spacing.s4) {
                        ForEach(event.attachments, id: \.self) { name in
                            let f = file(named: name)
                            if let f, let open = onOpenFile, loadStill != nil, AttachmentKinds.video.contains(AttachmentKinds.ext(of: f)) {
                                // A video is drawn as chat draws one: a 16:9 frame with a still and a play disc.
                                VideoFrameCard(title: f.title, size: f.size, loadStill: { await loadStill?(f) }, onTap: { open(f) })
                            } else {
                                AttachmentChip(name: name, onTap: f.flatMap { f in onOpenFile.map { open in { open(f) } } })
                            }
                        }
                    }
                }
            }
        }
    }
}

struct AttachmentChip: View {
    @Environment(\.appTheme) private var theme
    let name: String; var onTap: (() -> Void)?
    var body: some View {
        let c = theme.colors
        let tappable = onTap != nil
        let ext = name.split(separator: ".").last.map { $0.lowercased() } ?? ""
        let icon = !tappable ? "paperclip" : (AttachmentKinds.video.contains(ext) ? "play.circle" : (AttachmentKinds.image.contains(ext) ? "photo" : "eye"))
        HoverSurface(onTap: onTap, enabled: tappable, fill: tappable ? c.sel : c.panel2, border: tappable ? c.selLine : c.line, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: icon).font(.system(size: theme.sizes.icon12)).foregroundStyle(tappable ? c.accent : c.tx3)
                Text(name).font(theme.typography.caption).foregroundStyle(tappable ? c.accent : c.tx2).lineLimit(1)
            }
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
        }
    }
}
