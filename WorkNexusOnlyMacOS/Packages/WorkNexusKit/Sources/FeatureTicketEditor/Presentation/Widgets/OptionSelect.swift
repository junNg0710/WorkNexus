import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/option_select.dart
/// A searchable pick of one of `options`; with `noneValue` set, "None" is offered too and stands for it (`"0"` for
/// ids, `""` for text); nil when a choice is required.
struct OptionSelect: View {
    @Environment(\.appTheme) private var theme
    let options: [FormOption]
    let value: String
    var noneValue: String?
    let onChanged: (String) -> Void

    var body: some View {
        let none = appString("selectNone", "None")
        var items: [FormOption] = []
        if let noneValue { items.append(FormOption(value: noneValue, label: none)) }
        items += options
        // A value the list lacks (removed, or not yet loaded) still shows.
        if value != noneValue, !options.contains(where: { $0.value == value }) { items.append(FormOption(value: value, label: "#\(value)")) }
        return SearchableDropdownField(
            items: items, value: items.first { $0.value == value }, labelOf: \.label,
            hintText: none, searchHint: appString("searchOptions", "Search…"), emptyLabel: appString("noMatches", "No matches"),
            popoverMinWidth: theme.sizes.dialogMd, labelMaxLines: 2) { onChanged($0.value) }
    }
}
