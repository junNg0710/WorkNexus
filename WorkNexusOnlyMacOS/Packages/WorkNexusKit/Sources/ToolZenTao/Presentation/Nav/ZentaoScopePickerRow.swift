import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/nav/zentao_scope_picker_row.dart
/// The last row of the side panel's products / executions: opens the picker (`popover`, given a way to close it)
/// beside the panel, so a product or execution that is not pinned is a pick away here too.
struct ZentaoScopePickerRow<Popover: View>: View {
    @State private var open = false
    let label: String
    let popover: (_ close: @escaping () -> Void) -> Popover

    var body: some View {
        ScopeEntryRow(name: label, systemImage: "magnifyingglass", onTap: { open.toggle() })
            .popover(isPresented: $open, arrowEdge: .bottom) { popover { open = false } }
    }
}
