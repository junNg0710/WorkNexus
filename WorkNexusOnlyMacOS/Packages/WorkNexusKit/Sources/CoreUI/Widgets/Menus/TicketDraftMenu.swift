/// Not in the Flutter app (its draft picker only opened a draft).
import CoreDomain
import Foundation

/// The kept drafts of new bugs and tasks as menu rows, the same wherever they are offered: a board's "New bug" / "New
/// task" button, the rail's "+" and the editor's "Drafts (n)".
public enum TicketDraftMenu {
    /// A draft's title is cut to this many characters in a menu.
    public static let titleLength = 40

    /// `draft` as a menu row names it: its title (shortened) and when it was last written.
    public static func label(_ draft: ZenTaoSavedDraft, now: Date = Date()) -> String {
        var title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > titleLength { title = String(title.prefix(titleLength)).trimmingCharacters(in: .whitespaces) + "…" }
        return appFormat("ticketDraftLabel", "%1$@ · %2$@", title.isEmpty ? appString("ticketDraftUntitled", "Untitled") : title,
                         formatWhen(draft.updatedAt, now: now))
    }

    /// The row's name in a menu that also holds other things ("Draft: …").
    public static func named(_ label: String) -> String { appFormat("ticketDraftInMenu", "Draft: %1$@", label) }

    /// What a draft's row opens: go on writing it, or discard it.
    public static func choices(open: @escaping () -> Void, discard: @escaping () -> Void) -> [AppNativeMenu.Item] {
        [AppNativeMenu.Item(appString("ticketDraftOpen", "Continue writing"), icon: "square.and.pencil", action: open),
         AppNativeMenu.Item(appString("ticketDraftDiscard", "Discard draft"), icon: "trash", destructive: true, action: discard)]
    }

    /// One row per draft, then "Delete all drafts…" (`discardAll`, which asks first; nil leaves it out). `named`: the rows
    /// say they are drafts, for a menu that starts with something else; `dividerBefore` sets them apart from it.
    public static func items(_ drafts: [ZenTaoSavedDraft], named: Bool = false, dividerBefore: Bool = false, now: Date = Date(),
                             open: @escaping (ZenTaoSavedDraft) -> Void, discard: @escaping (ZenTaoSavedDraft) -> Void,
                             discardAll: (() -> Void)?) -> [AppNativeMenu.Item] {
        guard !drafts.isEmpty else { return [] }
        var rows = drafts.enumerated().map { i, d in
            let label = label(d, now: now)
            return AppNativeMenu.Item(named ? self.named(label) : label, dividerBefore: dividerBefore && i == 0,
                                      children: choices(open: { open(d) }, discard: { discard(d) }))
        }
        if let discardAll {
            rows.append(AppNativeMenu.Item(appString("ticketDraftsDeleteAllAsk", "Delete all drafts…"), icon: "trash", destructive: true,
                                           dividerBefore: true, action: discardAll))
        }
        return rows
    }
}
