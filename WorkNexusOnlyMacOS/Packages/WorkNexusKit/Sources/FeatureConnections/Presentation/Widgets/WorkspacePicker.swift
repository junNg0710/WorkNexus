import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/widgets/workspace_picker.dart
/// The workspace dropdown the connect dialog shares: existing workspaces plus a "New workspace…" entry
/// (`WorkspacePicker.newValue`). `nil` is "nothing picked yet" (several workspaces: the user must choose).
struct WorkspacePicker: View {
    @Environment(\.appTheme) private var theme
    static let newValue = "__new__"
    let workspaces: [Workspace]
    let value: String?
    let onChanged: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            Text(L.workspace).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
            AppDropdown(value: value ?? "", values: workspaces.map(\.id) + [Self.newValue],
                        labelOf: label(of:), onChanged: onChanged)
        }
    }

    private func label(of id: String) -> String {
        if id == Self.newValue { return L.newWorkspaceEntry }
        guard let w = workspaces.first(where: { $0.id == id }) else { return "" }
        return w.isPersonal ? L.personal : w.name
    }
}
