import CoreDomain
import CoreTools
import SwiftUI

/// The single documented entry of FeatureTicketEditor (lib/features/ticket_editor). The composition root does not
/// register anything; it only needs what is listed here.
///
/// ### Views
/// - `TicketEditorView(route:)` - the full-screen bug / task editor for `AppNavController.editor`. Services are
///   read from `\.services` (`AppServices.zentaoEditor`, `.zentaoDrafts`, `.zentaoTeamMembers`; all optional - without
///   `zentaoEditor` the page shows a retryable error state). Navigation comes from `.environment(\.ticketEditorNav, nav)`
///   or `TicketEditorView(route:nav:)`.
/// - `TicketEditorView(launch:)` - the same page opened with a `TicketEditorLaunch` (copy of a bug, bug filed against
///   a task, subtask of a task, a kept draft), which CoreTools' plain `TicketEditorRoute` cannot carry.
///
/// ### Models (UI-free logic, testable without a view)
/// `BugEditorController`, `TaskEditorController` (`@MainActor @Observable`), `ValidateBugDraft` / `ValidateTaskDraft`,
/// `ZenTaoChoices`, `EditorRules`, `DraftAutosave`.
///
/// ### Database
/// None of its own: kept drafts live in the `ticketDrafts` table owned by ToolZenTao (`ZenTaoMigrations.registrar`, id
/// `zentao_v1`) behind the hoisted `ZenTaoTicketDraftRepository`, so there is no migration registrar to pass to
/// `AppDatabase.open(registrars:)`.
public enum TicketEditorFeature {
    public static let name = "FeatureTicketEditor"

    /// The editor page for `route`.
    @MainActor
    public static func view(route: TicketEditorRoute, nav: AppNavController? = nil) -> some View {
        TicketEditorView(route: route, nav: nav)
    }

    /// The editor controllers over `services`, for hosts that render their own forms or test headlessly.
    @MainActor
    public static func makeBugController(launch: TicketEditorLaunch, services: AppServices?) -> BugEditorController {
        BugEditorController(launch: launch, gateway: TicketEditorGateway(services: services))
    }

    @MainActor
    public static func makeTaskController(launch: TicketEditorLaunch, services: AppServices?) -> TaskEditorController {
        TaskEditorController(launch: launch, gateway: TicketEditorGateway(services: services))
    }
}
