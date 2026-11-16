import AppKit
import Foundation

/// Not in the Flutter app: picking several tickets of a board, to act on them together.
public extension BoardController {
    /// A click on a card or a table row. ⌘ adds or removes it from the pick; ⇧ extends the pick from the last ticket
    /// picked through the ones in view (`among`, in the order they are drawn); a plain click opens the ticket - unless
    /// some are picked already, when it adds or removes too, so a pick is built by clicking.
    func tapTicket(_ id: String, among: [String] = []) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = selectionAnchor,
           let from = among.firstIndex(of: anchor), let to = among.firstIndex(of: id) {
            selectedIds.formUnion(among[min(from, to)...max(from, to)])
        } else if flags.contains(.command) || !selectedIds.isEmpty {
            toggleSelected(id)
        } else {
            openTicket(id)
        }
    }

    func toggleSelected(_ id: String) {
        if selectedIds.remove(id) == nil { selectedIds.insert(id); selectionAnchor = id }
    }

    /// Picks exactly `ids`.
    func select(_ ids: some Sequence<String>) {
        selectedIds = Set(ids)
        selectionAnchor = nil
    }

    func clearSelection() {
        if !selectedIds.isEmpty { selectedIds = [] }
        selectionAnchor = nil
    }
}
