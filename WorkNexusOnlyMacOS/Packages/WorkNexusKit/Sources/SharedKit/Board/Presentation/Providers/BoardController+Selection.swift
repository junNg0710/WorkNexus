import AppKit
import Foundation

/// Not in the Flutter app: picking several tickets of a board, to act on them together.
public extension BoardController {
    /// A click on a card or a table row. ⌘ adds or removes it from the pick; ⇧ extends the pick from the last ticket
    /// picked through the ones in view (`among`, in the order they are drawn); a plain click opens the ticket - unless
    /// picking mode is on or some are picked already, when it adds or removes too, so a pick is built by clicking.
    func tapTicket(_ id: String, among: [String] = []) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = selectionAnchor,
           let from = among.firstIndex(of: anchor), let to = among.firstIndex(of: id) {
            selectedIds.formUnion(among[min(from, to)...max(from, to)])
        } else if flags.contains(.command) || isSelecting || !selectedIds.isEmpty {
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

    /// Turns picking mode on (the board's Select button).
    func beginSelecting() { if !isSelecting { isSelecting = true } }

    /// Leaves picking mode and drops the pick (Done, Esc).
    func endSelecting() {
        clearSelection()
        if isSelecting { isSelecting = false }
    }

    /// Whether every one of `ids` is picked (a column's or the table's "all" checkbox).
    func allSelected(_ ids: [String]) -> Bool { !ids.isEmpty && ids.allSatisfy(selectedIds.contains) }

    /// Picks every one of `ids`, or drops them all when they are all picked already.
    func toggleAll(_ ids: [String]) {
        if allSelected(ids) { selectedIds.subtract(ids) } else { selectedIds.formUnion(ids) }
        selectionAnchor = nil
    }
}
