/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_find_bar.dart
import AppKit
import CoreUI
import SwiftUI

/// Find in the open document: the query (marked on the page once typing pauses), "3 of 12", previous / next. Enter goes
/// to the next result, Shift+Enter to the previous, Escape closes.
struct ZentaoDocFindBar: View {
    @Environment(\.appTheme) private var theme
    @State private var text: String
    let reader: ZentaoDocReader; let query: String
    /// The query to mark, once typing has paused.
    let onQuery: (String) -> Void; let onClose: () -> Void

    /// Re-marking a long page rebuilds it: wait for a pause in typing.
    static let pause: Duration = .milliseconds(250)

    init(reader: ZentaoDocReader, query: String, onQuery: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.reader = reader; self.query = query; self.onQuery = onQuery; self.onClose = onClose
        _text = State(initialValue: query)
    }

    var body: some View {
        ZentaoDocFloatingCard {
            HStack(spacing: theme.spacing.s6) {
                AppSearchField(text: $text, hint: appString("docsFindHint", "Find in this document"), autofocus: true, onSubmit: submit)
                Text(count).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                    .frame(minWidth: theme.sizes.control36 * 1.5).multilineTextAlignment(.center)
                ZentaoDocToolButton(systemImage: "chevron.up", help: appString("docsFindPrevious", "Previous result"), action: reader.previous)
                ZentaoDocToolButton(systemImage: "chevron.down", help: appString("docsFindNext", "Next result"), action: reader.next)
                ZentaoDocToolButton(systemImage: "xmark", help: appString("docsFindClose", "Close search"), action: onClose)
            }
        }
        .frame(width: theme.sizes.dialogMd)
        .onExitCommand(perform: onClose)
        .task(id: text) {
            try? await Task.sleep(for: Self.pause)
            if !Task.isCancelled, text != query { onQuery(text) }
        }
    }

    /// Enter marks the query at once while a pause is still pending, then steps through results.
    private func submit() {
        if text != query { onQuery(text) }
        else if NSEvent.modifierFlags.contains(.shift) { reader.previous() }
        else { reader.next() }
    }

    private var count: String {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        if reader.matchCount == 0 { return appString("docsFindNone", "No results") }
        return appFormat("docsFindCount", "%1$@ of %2$@", "\(reader.current + 1)", "\(reader.matchCount)")
    }
}
