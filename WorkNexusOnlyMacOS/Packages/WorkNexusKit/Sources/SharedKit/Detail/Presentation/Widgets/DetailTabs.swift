import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{detail_underline_tabs,detail_tab_bar}.dart
/// Tabs with an accent underline under the selected one, optional count badges.
public struct DetailUnderlineTabs<T: Hashable>: View {
    @Environment(\.appTheme) private var theme
    let labels: [(T, String)]; let current: T; let counts: [T: Int]; let onSelect: (T) -> Void

    public init(labels: [(T, String)], current: T, counts: [T: Int] = [:], onSelect: @escaping (T) -> Void) {
        self.labels = labels; self.current = current; self.counts = counts; self.onSelect = onSelect
    }

    public var body: some View {
        let c = theme.colors
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(labels, id: \.0) { key, label in
                    let selected = key == current
                    HoverSurface(onTap: { onSelect(key) }, selected: selected, height: theme.sizes.control36, cornerRadius: 0) {
                        HStack(spacing: theme.spacing.s6) {
                            Text(label).font(theme.typography.paragraph.weight(selected ? .semibold : .medium))
                                .foregroundStyle(selected ? c.tx : c.tx2).lineLimit(1)
                            if let n = counts[key] { AppCountBadge(n) }
                        }
                        .padding(.horizontal, theme.spacing.s14)
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(selected ? c.accent : .clear).frame(height: theme.borders.thick) }
                }
            }
            .padding(.horizontal, theme.spacing.s12)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
    }
}

/// Original / Translation tabs of the detail panel (the translation one only when the feature hook provides it).
struct DetailTabBar: View {
    let controller: DetailController; let ticket: Ticket; let model: TicketDetailModel
    var body: some View {
        var labels: [(DetailTab, String)] = [(.original, appString("original", "Original"))]
        if let l = controller.extensions.translationTabLabel?(ticket) { labels.append((.translation, l)) }
        return DetailUnderlineTabs(labels: labels, current: model.tab) { model.tab = $0 }
    }
}
