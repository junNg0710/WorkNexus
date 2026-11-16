/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_header.dart (`ZenTaoDocHeader`)
import CoreDomain
import CoreUI
import SwiftUI

/// The document's title, then who wrote and edited it (faces that open a card to message them), when, and how often it
/// was read - ruled off from the body below, as ZenTao's web sets a document's head apart.
struct ZentaoDocHeader: View {
    @Environment(\.appTheme) private var theme
    let accountId: String; let doc: ZenTaoDoc; let dateFormat: String

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 0) {
            // The page's title, above the body's own headings, as a document title reads on ZenTao's web.
            Text(doc.title).font(theme.typography.display).foregroundStyle(c.tx).lineSpacing(theme.typography.proseSize * 0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
            if doc.author != nil || !doc.editors.isEmpty {
                ZentaoFlow(spacing: theme.spacing.s12, lineSpacing: theme.spacing.s4) {
                    if let author = doc.author {
                        ZentaoDocPeople(accountId: accountId, people: [author], action: appString("docsCreatedAction", "created"),
                                        title: appString("docsPeopleCreated", "Created by"))
                    }
                    if !doc.editors.isEmpty {
                        ZentaoDocPeople(accountId: accountId, people: doc.editors, action: appString("docsEditedAction", "edited"),
                                        title: appString("docsPeopleEdited", "Edited by"))
                    }
                }
                .padding(.top, theme.spacing.s10)
            }
            if !facts.isEmpty {
                // Short facts, each kept whole: the line breaks between them, never inside one.
                ZentaoFlow(spacing: theme.spacing.s12, lineSpacing: theme.spacing.s4) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { i, fact in
                        HStack(spacing: theme.spacing.s12) {
                            if i > 0 { Text("·") }
                            fact
                        }
                    }
                }
                .font(theme.typography.paragraph).foregroundStyle(c.tx3)
                .padding(.top, theme.spacing.s6)
            }
            Divider().overlay(c.line).padding(.top, theme.spacing.s20)
        }
    }

    private var facts: [AnyView] {
        func day(_ d: Date) -> String { AppDateFormat.format(d, style: dateFormat) }
        var out: [AnyView] = []
        if let v = doc.version { out.append(AnyView(Text(appFormat("docsVersion", "Version %1$@", "\(v)")))) }
        if let created = doc.addedDate { out.append(AnyView(Text(appFormat("docsCreatedOn", "Created %1$@", day(created))))) }
        if let edited = doc.editedDate, edited != doc.addedDate {
            out.append(AnyView(Text(appFormat("docsEditedOn", "Edited %1$@", day(edited)))))
        }
        if let views = doc.views {
            out.append(AnyView(HStack(spacing: theme.spacing.s4) { Image(systemName: "eye"); Text("\(views)") }
                .help(appFormat("docsViews", "%1$@ views", "\(views)"))))
        }
        return out
    }
}

/// Children laid out left to right, wrapping onto a new line when the width runs out.
struct ZentaoFlow: Layout {
    var spacing: CGFloat; var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layout(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(subviews, width: bounds.width) {
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y + (row.height - item.height) / 2),
                                           proposal: ProposedViewSize(item.size))
            }
        }
    }

    private struct Row { var items: [(index: Int, x: CGFloat, size: CGSize, height: CGFloat)] = []; var y: CGFloat = 0; var height: CGFloat = 0; var width: CGFloat = 0 }

    private func layout(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [], row = Row(), x: CGFloat = 0, y: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                row.y = y; rows.append(row); y += row.height + lineSpacing; row = Row(); x = 0
            }
            row.items.append((i, x, size, size.height))
            row.height = max(row.height, size.height); x += size.width; row.width = x; x += spacing
        }
        if !row.items.isEmpty { row.y = y; rows.append(row) }
        return rows
    }
}
