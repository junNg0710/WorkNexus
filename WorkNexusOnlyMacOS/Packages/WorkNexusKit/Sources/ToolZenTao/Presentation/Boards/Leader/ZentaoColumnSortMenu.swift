/// Not in the Flutter app.
import CoreUI
import SwiftUI

/// How the cards inside each column are ordered: by priority (the default) or by deadline, the most overdue first.
struct ZentaoColumnSortMenu: View {
    @Bindable var state: ZentaoUIState

    var body: some View {
        AppDropdown(value: state.columnSort, values: ZenTaoColumnSort.allCases,
                    labelOf: { $0 == .deadline ? appString("leaderSortDeadline", "Sort: deadline") : appString("leaderSortPriority", "Sort: priority") },
                    help: appString("leaderSortHelp", "Order of the cards in each column"),
                    onChanged: { state.columnSort = $0 })
        .fixedSize()
    }
}
