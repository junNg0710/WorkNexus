import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/option_check_list.dart
/// The options as checkable rows; `emptyLabel` when none match.
struct OptionCheckList: View {
    @Environment(\.appTheme) private var theme
    let options: [FormOption]
    let picked: Set<String>
    let emptyLabel: String
    let onToggle: (String) -> Void

    var body: some View {
        if options.isEmpty {
            Text(emptyLabel).font(theme.typography.body).foregroundStyle(theme.colors.tx3).frame(maxWidth: .infinity).padding(theme.spacing.s16)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(options, id: \.value) { o in
                        CheckRow(label: o.label, checked: picked.contains(o.value)) { onToggle(o.value) }
                    }
                }
                .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
            }
        }
    }
}

private struct CheckRow: View {
    @Environment(\.appTheme) private var theme
    let label: String
    let checked: Bool
    let onTap: () -> Void

    var body: some View {
        HoverSurface(onTap: onTap, selected: checked) {
            HStack(spacing: theme.spacing.s10) {
                Image(systemName: checked ? "checkmark.square.fill" : "square").font(.system(size: theme.sizes.icon18))
                    .foregroundStyle(checked ? theme.colors.accent : theme.colors.tx3)
                Text(label).font(theme.typography.body).fontWeight(checked ? .medium : nil).foregroundStyle(theme.colors.tx).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s8)
        }
    }
}
