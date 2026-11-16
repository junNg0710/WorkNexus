import CoreDomain
import SwiftUI

/// Everything presentation may depend on — interfaces only (rules 1.3/8.2). Built once by the composition root
/// (`App/Sources`) and injected through the SwiftUI environment as `\.services`.
public struct AppServices: Sendable {
    public var tickets: TicketRepository
    public var workspaces: WorkspaceRepository
    public var comments: CommentRepository
    public var activity: ActivityRepository
    public var syncStatus: SyncStatusRepository
    public var settings: SettingsRepository
    public var credentials: CredentialStore
    public var sync: AccountSyncService
    public var ticketDetail: TicketDetailService
    public var adapters: ProviderAdapterRegistry

    // Optional ZenTao-facing hooks (contracts hoisted into CoreDomain/Adapters so features never import ToolZenTao).
    // nil until the composition root wires them (`services.zentaoEditor = ...`); the init above stays source-compatible.
    /// ZenTao web notifications, local-first (notifications feature).
    public var zentaoMessages: ZenTaoNotificationRepository?
    /// The "my work" dashboard snapshot of a ZenTao account (workspace overview).
    public var zentaoDashboard: ZenTaoDashboardRepository?
    /// Bug / task create + edit forms and image upload (ticket editor).
    public var zentaoEditor: ZenTaoTicketEditor?
    /// Product / execution members, for the assignee choices.
    public var zentaoTeamMembers: ZenTaoTeamMembers?
    /// Unsaved new-bug / new-task drafts (ticket editor).
    public var zentaoDrafts: ZenTaoTicketDraftRepository?
    /// Single-ticket fetch and products / projects / executions listing.
    public var zentaoTickets: ZenTaoTicketService?
    /// Bug / task status actions.
    public var zentaoWorkflow: ZenTaoWorkflowService?

    public init(tickets: TicketRepository, workspaces: WorkspaceRepository, comments: CommentRepository,
                activity: ActivityRepository, syncStatus: SyncStatusRepository, settings: SettingsRepository,
                credentials: CredentialStore, sync: AccountSyncService, ticketDetail: TicketDetailService,
                adapters: ProviderAdapterRegistry) {
        self.tickets = tickets; self.workspaces = workspaces; self.comments = comments; self.activity = activity
        self.syncStatus = syncStatus; self.settings = settings; self.credentials = credentials; self.sync = sync
        self.ticketDetail = ticketDetail; self.adapters = adapters
    }
}

private struct ServicesKey: EnvironmentKey { static let defaultValue: AppServices? = nil }
public extension EnvironmentValues {
    var services: AppServices? {
        get { self[ServicesKey.self] }
        set { self[ServicesKey.self] = newValue }
    }
}
