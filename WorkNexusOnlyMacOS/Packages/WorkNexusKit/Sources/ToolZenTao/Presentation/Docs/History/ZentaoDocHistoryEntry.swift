/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_history_entry.dart
import CoreDomain
import CoreUI
import SwiftUI

/// One numbered entry of a document's history: when, who, what - and, behind its "+", what changed.
struct ZentaoDocHistoryEntry: View {
    @Environment(\.appTheme) private var theme
    @State private var open = false
    let number: Int; let entry: ZenTaoDocAction; let last: Bool; let dateFormat: String

    var body: some View {
        let c = theme.colors
        let dot = theme.sizes.icon20
        HStack(alignment: .top, spacing: theme.spacing.s10) {
            // The numbered dot, on a line joining it to the next entry.
            VStack(spacing: 0) {
                Text("\(number)").font(theme.typography.caption).foregroundStyle(c.tx2)
                    .frame(width: dot, height: dot).background(c.card, in: Circle()).overlay(Circle().stroke(c.line))
                if !last { Rectangle().fill(c.line).frame(width: theme.borders.hairline).frame(maxHeight: .infinity) }
            }
            .frame(width: dot)
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                // Who did what, then when.
                (Text(Self.sentence(entry, plain: theme, name: c)) + Text(date.map { "  \($0)" } ?? "")
                    .font(theme.typography.caption).foregroundStyle(c.tx3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if open && !entry.changes.isEmpty { ZentaoDocHistoryChanges(changes: entry.changes) }
            }
            .padding(.bottom, theme.spacing.s12)
            if !entry.changes.isEmpty {
                Button { open.toggle() } label: {
                    Image(systemName: open ? "minus" : "plus").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx2)
                        .frame(width: dot, height: dot)
                        .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(c.line, lineWidth: theme.borders.hairline))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(open ? appString("docsHideChanges", "Hide what changed") : appString("docsShowChanges", "Show what changed"))
            }
        }
    }

    private var date: String? { entry.date.map { AppDateFormat.format($0, style: dateFormat, withTime: true) } }

    /// The sentence with the actor's name standing out from the words around it.
    static func sentence(_ e: ZenTaoDocAction, plain theme: AppTheme, name c: AppPalette) -> AttributedString {
        let text = sentence(e)
        var a = AttributedString(text)
        a.font = theme.typography.paragraph; a.foregroundColor = c.tx2
        if let actor = e.actor, !actor.isEmpty, let r = a.range(of: actor) {
            a[r].font = theme.typography.paragraph.weight(.semibold); a[r].foregroundColor = c.tx
        }
        return a
    }

    /// "ViPham edited it" in the app's language for the actions it knows; ZenTao's own sentence otherwise.
    static func sentence(_ e: ZenTaoDocAction) -> String {
        guard let name = e.actor else { return e.summary }
        switch e.action {
        case "created", "opened": return appFormat("docsActionCreated", "%1$@ created it", name)
        case "edited": return appFormat("docsActionEdited", "%1$@ edited it", name)
        case "saveddraft": return appFormat("docsActionSavedDraft", "%1$@ saved a draft", name)
        case "moved": return appFormat("docsActionMoved", "%1$@ moved it", name)
        case "releaseddoc", "released": return appFormat("docsActionReleased", "%1$@ released it", name)
        case "commented": return appFormat("docsActionCommented", "%1$@ commented", name)
        default: return e.summary
        }
    }
}
