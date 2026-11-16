/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_history_changes.dart
import CoreDomain
import CoreUI
import SwiftUI

/// What a history entry changed, field by field: an old value struck through and the new one beside it, a text diff's
/// removed and added lines, or - for the body, which ZenTao records as the editor's raw page - just that it changed.
/// Long values are cut to a few lines.
struct ZentaoDocHistoryChanges: View {
    @Environment(\.appTheme) private var theme
    let changes: [ZenTaoDocChange]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in ZentaoDocChangeRow(change: change) }
        }
        .padding(theme.spacing.s8).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.sm))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

private struct ZentaoDocChangeRow: View {
    @Environment(\.appTheme) private var theme
    let change: ZenTaoDocChange

    /// Lines of a value shown before it is cut.
    static let lines = 3

    var body: some View {
        let c = theme.colors
        let mono = Font.custom("Space Mono", size: 13)
        VStack(alignment: .leading, spacing: theme.spacing.s2) {
            Text(change.field).font(theme.typography.label).foregroundStyle(c.tx2)
            if change.isBody {
                Text(appString("docsBodyChanged", "The document's content changed")).font(theme.typography.paragraph).foregroundStyle(c.tx3)
            } else if !change.removed.isEmpty || !change.added.isEmpty {
                // A text diff is often code: mono keeps its columns.
                ForEach(Array(change.removed.enumerated()), id: \.offset) { _, line in
                    Text(line).font(mono).strikethrough().foregroundStyle(c.red).lineLimit(Self.lines)
                }
                ForEach(Array(change.added.enumerated()), id: \.offset) { _, line in
                    Text(line).font(mono).foregroundStyle(c.green).lineLimit(Self.lines)
                }
            } else {
                (Text(shown(change.from)).strikethrough().foregroundColor(c.red) + Text("  →  ").foregroundColor(c.tx3)
                    + Text(shown(change.to)).foregroundColor(c.green))
                    .font(theme.typography.paragraph).lineLimit(Self.lines * 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shown(_ v: String?) -> String {
        (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? appString("docsEmptyValue", "(empty)") : v!
    }
}
