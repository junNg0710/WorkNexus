/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SwiftUI

/// The line a new module's name is typed on, in the tree where the module will be: Return adds it to ZenTao (the tree
/// then lists it), Esc gives up. What is wrong with the name, or why ZenTao refused it, shows under the field.
struct ZentaoModuleAddRow: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState
    let bugs: Bool
    /// The module it goes inside, or nil for the top of the tree.
    let parentId: String?
    let depth: Int
    let onDone: () -> Void
    @State private var name = ""
    @State private var saving = false
    @State private var refused: String?
    @FocusState private var focused: Bool

    /// What the tree's "adding at the top" state is keyed by (no module has an empty id).
    static let top = ""

    var body: some View {
        let c = theme.colors
        let problem = name.isEmpty ? nil : state.moduleNameProblem(name, parentId: parentId, bugs: bugs)
        let wrong = problem.map(Self.label) ?? refused
        VStack(alignment: .leading, spacing: theme.spacing.s2) {
            HStack(spacing: theme.spacing.s6) {
                Image(systemName: depth == 0 ? "folder.badge.plus" : "arrow.turn.down.right")
                    .font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx3)
                TextField("", text: $name, prompt: Text(appString("zentaoModuleNameHint", "Module name")).foregroundStyle(c.tx3))
                    .textFieldStyle(.plain).font(theme.typography.body).foregroundStyle(c.tx)
                    .focused($focused).disabled(saving).onSubmit(add)
                if saving { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, theme.spacing.s8).frame(height: theme.sizes.control32)
            .background(c.card, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(wrong == nil ? c.accent : c.red, lineWidth: theme.borders.hairline))
            Text(wrong ?? appString("zentaoModuleAddHint", "Return adds it to ZenTao, Esc cancels"))
                .font(theme.typography.caption).foregroundStyle(wrong == nil ? c.tx3 : c.red)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, theme.spacing.s4)
        }
        .padding(.leading, theme.spacing.s12 * CGFloat(depth)).padding(.vertical, theme.spacing.s4)
        .onAppear { focused = true }
        .onExitCommand { if !saving { onDone() } }
        .onChange(of: name) { _, _ in refused = nil }
    }

    private func add() {
        guard !saving, state.moduleNameProblem(name, parentId: parentId, bugs: bugs) == nil else { return }
        saving = true
        Task {
            let failure = await state.addModule(name, parentId: parentId, bugs: bugs)
            saving = false
            if let failure { refused = failure.message; focused = true } else { onDone() }
        }
    }

    static func label(_ problem: ZenTaoModuleNameProblem) -> String {
        switch problem {
        case .empty: appString("zentaoModuleNameEmpty", "A module needs a name")
        case .tooLong: appFormat("zentaoModuleNameTooLong", "A module name can be %1$@ characters at most", "\(CheckZenTaoModuleName.maxLength)")
        case .hasSlash: appString("zentaoModuleNameSlash", "A module name cannot contain a slash")
        case .exists: appString("zentaoModuleExists", "A module with this name is already there")
        }
    }
}
