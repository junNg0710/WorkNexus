import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

private struct TicketEditorNavKey: EnvironmentKey { static let defaultValue: AppNavController? = nil }
public extension EnvironmentValues {
    /// The navigation controller `TicketEditorView` closes itself on and opens the saved ticket through, when it was
    /// not given one explicitly. The composition root may set it once on the shell.
    var ticketEditorNav: AppNavController? {
        get { self[TicketEditorNavKey.self] }
        set { self[TicketEditorNavKey.self] = newValue }
    }
}

/// Ported from: lib/features/ticket_editor/presentation/pages/ticket_editor_page.dart
/// The full-screen page that adds or edits a ZenTao bug or task - what the shell shows while
/// `AppNavController.editor` is set. Services come from `\.services` (the optional `zentaoEditor`,
/// `zentaoDrafts`, `zentaoTeamMembers` hooks); without an editor the page shows its error state. Cancel, a finished
/// save and "discard draft" call `nav.closeEditor()`; a saved ticket is opened with `nav.openTicket`.
public struct TicketEditorView: View {
    @Environment(\.services) private var services
    @Environment(\.ticketEditorNav) private var environmentNav
    @Environment(\.appTheme) private var theme
    @State private var launch: TicketEditorLaunch
    /// Bumped for each fresh form in this view, so its controller starts over (also when the launch is the same).
    @State private var epoch = 0
    private let explicitNav: AppNavController?

    /// - Parameters:
    ///   - route: `AppNavController.editor`.
    ///   - nav: defaults to `\.ticketEditorNav`.
    public init(route: TicketEditorRoute, nav: AppNavController? = nil) {
        self.init(launch: Self.launch(for: route), nav: nav)
    }

    /// Opens with everything a Flutter `TicketEditorRoute` carries (copy of, subtask of, kept draft...).
    public init(launch: TicketEditorLaunch, nav: AppNavController? = nil) {
        _launch = State(initialValue: launch)
        explicitNav = nav
    }

    /// The nav route as a launch. An edit route's `ticketId` is the WorkNexus ticket id (`{account}:{type}:{id}`);
    /// the ZenTao id is read out of it.
    public static func launch(for route: TicketEditorRoute) -> TicketEditorLaunch {
        switch route {
        case .newBug(let account, let product, let execution, let copyOf, let task):
            .newBug(accountId: account, productId: product ?? "0", copyOf: copyOf, executionId: execution, taskId: task)
        case .newTask(let account, let execution, let copyOf, let parent, let fromBug):
            .newTask(accountId: account, executionId: execution ?? "0", parentId: parent, copyOf: copyOf, fromBug: fromBug)
        case .editBug(let account, let ticketId): .editBug(accountId: account, bugId: TicketEditorLaunch.zenTaoId(from: ticketId))
        case .editTask(let account, let ticketId): .editTask(accountId: account, taskId: TicketEditorLaunch.zenTaoId(from: ticketId))
        }
    }

    private struct FormKey: Hashable { let launch: TicketEditorLaunch; let epoch: Int }

    /// What the new ticket starts filled in with (made from a chat message), from the nav state that opened the editor.
    private var prefill: TicketEditorPrefill? { (explicitNav ?? environmentNav)?.editorPrefill }

    private var actions: EditorActions {
        let nav = explicitNav ?? environmentNav
        return EditorActions(
            close: { nav?.closeEditor() },
            openTicket: { nav?.openTicket($0) },
            switchTo: { launch = $0; epoch += 1 },
            startOver: { launch = $0; epoch += 1 })
    }

    public var body: some View {
        let gateway = TicketEditorGateway(services: services)
        ZStack {
            theme.colors.bg
            if launch.isBug {
                BugEditorView(launch: launch, gateway: gateway, actions: actions, prefill: prefill).id(FormKey(launch: launch, epoch: epoch))
            } else {
                TaskEditorView(launch: launch, gateway: gateway, actions: actions, prefill: prefill).id(FormKey(launch: launch, epoch: epoch))
            }
        }
    }
}
