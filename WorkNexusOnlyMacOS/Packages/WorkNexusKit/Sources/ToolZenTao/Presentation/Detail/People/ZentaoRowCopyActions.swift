/// Ported from: lib/tools/zentao/presentation/widgets/zentao_row_copy_actions.dart, zentao_card_parent.dart
import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// What a row's copy actions put on the clipboard (Title, ID, Markdown link, Link).
public enum ZentaoCopyText {
    public static func title(_ t: Ticket) -> String { t.title }
    public static func id(_ t: Ticket) -> String { "#\(t.externalKey)" }
    public static func markdownLink(_ t: Ticket) -> String {
        let url = t.url ?? ""
        return url.isEmpty ? "[#\(t.externalKey)] \(t.title)" : "[#\(t.externalKey) \(t.title)](\(url))"
    }
    public static func link(_ t: Ticket) -> String? { (t.url ?? "").isEmpty ? nil : t.url }

    /// The menu entries in order, each with the text it copies and the toast it shows.
    static func entries(_ t: Ticket) -> [(icon: String, label: String, text: String, toast: String)] {
        var out = [
            ("doc.on.doc", appString("copyTitle", "Copy title"), title(t), appString("titleCopied", "Title copied")),
            ("number", "\(appString("copyId", "Copy ID")) (#\(t.externalKey))", id(t), appString("idCopied", "ID copied")),
            ("chevron.left.forwardslash.chevron.right", appString("copyMarkdownLink", "Copy Markdown link"), markdownLink(t),
             appString("markdownLinkCopied", "Markdown link copied")),
        ]
        if let l = link(t) { out.append(("link", appString("copyLink", "Copy link"), l, appString("linkCopied", "Copied!"))) }
        return out
    }
}

/// The copy actions of a task or bug row as a menu (Title, ID, Markdown link, Link). `deps` / `state` are accepted so
/// every embedded ZenTao view is built the same way.
public struct ZentaoCopyActionsMenu: View {
    @Environment(\.toasts) private var toasts
    let ticket: Ticket
    public init(deps: ZentaoDependencies? = nil, state: ZentaoUIState? = nil, ticket: Ticket) { self.ticket = ticket }

    public var body: some View {
        Menu {
            ForEach(Array(ZentaoCopyText.entries(ticket).enumerated()), id: \.offset) { _, e in
                Button { copy(e.text, e.toast) } label: { Label(e.label, systemImage: e.icon) }
            }
        } label: { Image(systemName: "doc.on.doc") }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
        .help(appString("copyTitle", "Copy title"))
    }

    private func copy(_ text: String, _ toast: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        toasts?.show(toast)
    }
}

public extension View {
    /// A right-click menu with the row's copy actions.
    func zentaoRowContextMenu(ticket: Ticket) -> some View { modifier(ZentaoRowContextMenu(ticket: ticket)) }
}

private struct ZentaoRowContextMenu: ViewModifier {
    @Environment(\.toasts) private var toasts
    let ticket: Ticket
    func body(content: Content) -> some View {
        let entries = ZentaoCopyText.entries(ticket)
        content.appContextMenu(entries: entries.map { AppMenuEntry(icon: $0.icon, label: $0.label) }) { i in
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entries[i].text, forType: .string)
            toasts?.show(entries[i].toast)
        }
    }
}

/// A compact, quick copy-title button revealed when hovering over a task or bug row.
public struct ZentaoRowQuickCopyButton: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let ticket: Ticket
    @State private var copied = false
    public init(ticket: Ticket) { self.ticket = ticket }

    public var body: some View {
        let c = theme.colors
        HoverSurface(onTap: copy, fill: copied ? c.green.opacity(0.15) : c.tx3.opacity(0.08), cornerRadius: theme.radii.xs) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11)).foregroundStyle(copied ? c.green : c.tx2).padding(3)
        }
        .help(copied ? appString("titleCopied", "Title copied") : appString("copyTitle", "Copy title"))
    }

    private func copy() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ticket.title, forType: .string)
        toasts?.show(appString("titleCopied", "Title copied"))
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}

/// A subtask card's parent task, its number and title, so a subtask can be placed without opening it. Display only: the
/// whole card is the tap target. Nothing for a ticket that is not a subtask. The parent's title is the one ZenTao
/// gave, else the synced parent's (read through `\.services`).
public struct ZentaoCardParentLine: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.services) private var services
    let ticket: Ticket
    @State private var syncedName: String?
    public init(ticket: Ticket) { self.ticket = ticket }

    private var parent: (id: String, name: String?)? {
        if case .zentaoTask(let t) = ticket.providerEntity, let id = t.parentId { return (id, t.parentName) }
        return nil
    }

    public var body: some View {
        if let parent {
            let c = theme.colors
            let name = parent.name ?? syncedName
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: "arrow.turn.left.up").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3)
                Text("#\(parent.id)").font(theme.typography.mono).foregroundStyle(c.tx3)
                if let name { Text(name).font(theme.typography.caption).foregroundStyle(c.tx3).lineLimit(1) }
            }
            .help([appString("parentTask", "Parent task"), "#\(parent.id)", name].compactMap { $0 }.joined(separator: " "))
            .task(id: parent.id) {
                guard parent.name == nil, let services else { return }
                let id = zenTaoTicketId(accountId: ticket.accountId, type: "task", id: parent.id)
                if case .success(let t) = await services.tickets.ticket(id: id) { syncedName = t?.title }
            }
        }
    }
}
