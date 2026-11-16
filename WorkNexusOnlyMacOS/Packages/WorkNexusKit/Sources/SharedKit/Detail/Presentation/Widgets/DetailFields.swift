import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{detail_field_rows,detail_fields_card,empty_fields_toggle}.dart
/// Label / value rows with hairline separators.
public struct DetailFieldRows: View {
    @Environment(\.appTheme) private var theme
    let rows: [(String, String)]; var labelWidth: CGFloat; var alignEnd: Bool; var valueViews: [String: AnyView]

    public init(rows: [(String, String)], labelWidth: CGFloat = 120, alignEnd: Bool = false, valueViews: [String: AnyView] = [:]) {
        self.rows = rows; self.labelWidth = labelWidth; self.alignEnd = alignEnd; self.valueViews = valueViews
    }

    public var body: some View {
        let c = theme.colors
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 0) {
                    Text(row.0).font(theme.typography.meta).foregroundStyle(c.tx3).frame(width: labelWidth, alignment: .leading)
                    Group {
                        if let v = valueViews[row.0] { v } else {
                            Text(row.1).font(theme.typography.paragraph).foregroundStyle(c.tx).multilineTextAlignment(alignEnd ? .trailing : .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: alignEnd ? .trailing : .leading)
                }
                .padding(.vertical, theme.spacing.s6)
                .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 1) }
            }
        }
    }
}

/// A titled group of rows (hidden when empty).
public struct DetailSection: View {
    @Environment(\.appTheme) private var theme
    let title: String; let rows: [(String, String)]
    public init(title: String, rows: [(String, String)]) { self.title = title; self.rows = rows }
    public var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.s4) { SectionLabel(title); DetailFieldRows(rows: rows) }
        }
    }
}

/// The sidebar metadata card (Flutter `DetailMetaCard` / `DetailFieldsCard`): a title, right-aligned rows (a row may
/// carry its own view), and extra children under them.
public struct DetailFieldsCard<Extra: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String; let rows: [(String, String)]; let valueViews: [String: AnyView]; let extra: Extra
    public static var labelWidth: CGFloat { 100 }

    public init(title: String, rows: [(String, String)], valueViews: [String: AnyView] = [:], @ViewBuilder extra: () -> Extra) {
        self.title = title; self.rows = rows; self.valueViews = valueViews; self.extra = extra()
    }

    public var body: some View {
        DetailRegionCard(padding: theme.spacing.s12) {
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                SectionLabel(title)
                DetailFieldRows(rows: rows, labelWidth: Self.labelWidth, alignEnd: true, valueViews: valueViews)
                extra
            }
        }
    }
}

public extension DetailFieldsCard where Extra == EmptyView {
    init(title: String, rows: [(String, String)], valueViews: [String: AnyView] = [:]) {
        self.init(title: title, rows: rows, valueViews: valueViews) { EmptyView() }
    }
}

/// "Show N empty fields" / "Hide empty fields" link under a field list.
public struct EmptyFieldsToggle: View {
    @Environment(\.appTheme) private var theme
    let count: Int; let expanded: Bool; let onTap: () -> Void
    @State private var hovered = false
    public init(count: Int, expanded: Bool, onTap: @escaping () -> Void) { self.count = count; self.expanded = expanded; self.onTap = onTap }
    public var body: some View {
        Button(action: onTap) {
            Text(expanded ? appString("hideEmptyFields", "Hide empty fields") : appFormat("showEmptyFields", "Show %1$@ empty fields", "\(count)"))
                .font(theme.typography.caption).foregroundStyle(theme.colors.accent).underline(hovered, color: theme.colors.accent)
                .padding(.vertical, theme.spacing.s6)
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
