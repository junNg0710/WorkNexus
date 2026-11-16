import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/{option_multi_select,option_multi_select_dialog}.dart
/// A pick of any number of `options`, shown as removable chips; clicking the field opens a searchable checklist
/// (a popover here instead of Flutter's dialog): the ticks are a draft that applies when the popover is dismissed,
/// as the dialog's Save did (the chips under it change once it closes).
struct OptionMultiSelect: View {
    @Environment(\.appTheme) private var theme
    @State private var open = false
    @State private var query = ""
    /// The ticks while the popover is open; handed to `onChanged` when it closes.
    @State private var draft: [String] = []
    let title: String
    let options: [FormOption]
    let values: [String]
    let onChanged: ([String]) -> Void

    private func label(_ value: String) -> String { options.first { $0.value == value }?.label ?? value }

    var body: some View {
        HoverSurface(onTap: { query = ""; open.toggle() }, fill: theme.colors.panel2, border: theme.colors.line) {
            HStack(alignment: .top, spacing: theme.spacing.s6) {
                if values.isEmpty {
                    Text(appString("selectNone", "None")).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx3)
                        .padding(.vertical, theme.spacing.s6)
                } else {
                    FlowLayout(spacing: theme.spacing.s6) {
                        ForEach(values, id: \.self) { v in EditorChip(label: label(v)) { onChanged(values.filter { $0 != v }) } }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3)
                    .padding(.top, theme.spacing.s8)
            }
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s4)
            .frame(minHeight: theme.sizes.control32)
        }
        .popover(isPresented: $open, arrowEdge: .bottom) { picker }
        .onChange(of: open) { _, isOpen in
            if isOpen { draft = values } else if draft != values { onChanged(draft) }
        }
    }

    private var shown: [FormOption] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? options : options.filter { $0.label.lowercased().contains(q) }
    }

    /// `values` with `value` ticked or unticked: in the options' order, keeping picks the list does not have.
    static func toggled(_ values: [String], _ value: String, options: [FormOption]) -> [String] {
        if values.contains(value) { return values.filter { $0 != value } }
        let picked = Set(values + [value])
        return options.map(\.value).filter(picked.contains) + values.filter { v in !options.contains { $0.value == v } && v != value }
    }

    private func toggle(_ value: String) { draft = Self.toggled(draft, value, options: options) }

    private var picker: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                Spacer()
                if !draft.isEmpty {
                    Text(appFormat("selectSome", "%1$@ selected", "\(draft.count)")).font(theme.typography.meta).foregroundStyle(theme.colors.accent)
                }
            }
            .padding(.horizontal, theme.spacing.s12).padding(.top, theme.spacing.s12)
            AppSearchField(text: $query, hint: appString("searchOptions", "Search…"), autofocus: true).padding(theme.spacing.s8)
            Divider().overlay(theme.colors.line)
            OptionCheckList(options: shown, picked: Set(draft), emptyLabel: appString("noMatches", "No matches"), onToggle: toggle)
                .frame(height: 260)
        }
        .frame(width: theme.sizes.dialogSm - theme.spacing.s40)
    }
}
