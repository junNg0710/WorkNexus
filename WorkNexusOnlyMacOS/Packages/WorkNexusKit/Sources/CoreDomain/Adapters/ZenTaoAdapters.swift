import Foundation

/// A raw ZenTao JSON reply (PHP-shaped, loosely typed), carried across the layer boundary as-is.
public struct ZenTaoRawReply: @unchecked Sendable {
    public let json: [String: Any]
    public init(_ json: [String: Any]) { self.json = json }
}

/// Ported from: lib/core/domain/adapters/zentao_messages_adapter.dart
public protocol ZenTaoMessagesAdapter: ProviderAdapter {
    /// The raw view of the web notification menu (`allMessages` by day).
    func fetchMessages() async -> Outcome<ZenTaoRawReply>
    /// Runs a classic message action, e.g. `ajaxMarkRead-all`, `ajaxDelete-12`.
    func messageAction(_ action: String) async -> Outcome<Void>
    /// The raw `GET /user?fields=...` reply (profile + "my work" blocks) that the dashboard is built from.
    func fetchUserInfo(fields: String, limit: Int) async -> Outcome<ZenTaoRawReply>
}

/// Ported from: lib/core/domain/adapters/zentao_workflow_service.dart
/// ZenTao's status actions on bugs and tasks. Each shows its outcome on the ticket at once, then refreshes it
/// from ZenTao (or puts it back on failure).
public protocol ZenTaoWorkflowService: Sendable {
    func confirmBug(_ ticket: Ticket, assignee: String?, comment: String?) async -> Outcome<Void>
    func activateBug(_ ticket: Ticket, build: String?, assignee: String?, comment: String?) async -> Outcome<Void>
    func resolveBug(_ ticket: Ticket, resolution: String, build: String?, assignee: String?, comment: String?) async -> Outcome<Void>
    func closeBug(_ ticket: Ticket, comment: String?) async -> Outcome<Void>
    func runTaskAction(_ ticket: Ticket, _ action: ZenTaoTaskAction, _ input: ZenTaoTaskActionInput) async -> Outcome<Void>
    /// Deletes the bug or task in ZenTao (it goes to ZenTao's recycle bin).
    func deleteTicket(_ ticket: Ticket) async -> Outcome<Void>
}

/// Shows `optimistic` for `original` at once (writing it to the local DB), runs `action`, then refreshes the
/// ticket from ZenTao - or puts `original` back when `action` fails. Implemented by the sync layer
/// (SyncCoordinator.runOptimisticAction in the Flutter app); injected by the composition root.
public protocol ZenTaoOptimisticRunner: Sendable {
    func runOptimisticAction(_ original: Ticket, _ optimistic: Ticket,
                             _ action: @escaping @Sendable () async -> Outcome<Void>) async -> Outcome<Void>
}

/// Ported from: lib/core/domain/adapters/zentao_ticket_editor.dart
/// Creates and edits ZenTao bugs and tasks through ZenTao's own web forms.
public protocol ZenTaoTicketEditor: Sendable {
    func newBugForm(accountId: String, productId: String, copyOf: String?, executionId: String?, taskId: String?) async -> Outcome<BugForm>
    func editBugForm(accountId: String, bugId: String) async -> Outcome<BugForm>
    func bugOptions(accountId: String, productId: String, projectId: String, executionId: String) async -> Outcome<BugFormOptions>
    func bugModules(accountId: String, productId: String) async -> Outcome<[FormOption]>
    /// Saves `draft` (a new bug when its id is nil); returns the bug's WorkNexus ticket id.
    func saveBug(accountId: String, form: BugForm, draft: BugDraft, uid: String) async -> Outcome<String>
    /// `fromBug`: the task is made from that bug (ZenTao's "Convert to Task"), which then names the task it became.
    func newTaskForm(accountId: String, executionId: String, parentId: String?, copyOf: String?, fromBug: String?) async -> Outcome<TaskForm>
    func editTaskForm(accountId: String, taskId: String) async -> Outcome<TaskForm>
    func taskOptions(accountId: String, executionId: String) async -> Outcome<TaskFormOptions>
    func saveTask(accountId: String, form: TaskForm, draft: TaskDraft, uid: String) async -> Outcome<String>
    /// An image in a description (behind ZenTao's sign-in), or nil.
    func loadImage(accountId: String, url: String) async -> Data?
    /// Uploads an image put into a description; returns the URL to embed it at.
    func uploadImage(accountId: String, uid: String, bytes: Data, fileName: String) async -> Outcome<String>
}

/// Ported from: lib/core/domain/adapters/zentao_ticket_service.dart
/// Loads a single ZenTao ticket on demand, or syncs ZenTao products/projects/executions.
public protocol ZenTaoTicketService: Sendable {
    /// Fetches bug/task/story `id` of `type` from the connected ZenTao account on `host`, stores it and returns
    /// its WorkNexus ticket id.
    func fetchZenTaoTicket(host: String, type: String, id: String) async -> Outcome<String>
    func listProducts(accountId: String) async -> Outcome<[ProviderProduct]>
    func cachedProducts(accountId: String) async -> [ProviderProduct]?
    func listProjects(accountId: String) async -> Outcome<[ProviderProject]>
    func cachedProjects(accountId: String) async -> [ProviderProject]?
    func listProjectExecutions(accountId: String, projectId: String) async -> Outcome<[ProviderExecution]>
    func fetchZenTaoMessages(accountId: String) async -> Outcome<ZenTaoRawReply>
    func zenTaoMessageAction(accountId: String, action: String) async -> Outcome<Void>
    func fetchZenTaoUserInfo(accountId: String, fields: String, limit: Int) async -> Outcome<ZenTaoRawReply>
}

/// Ported from: lib/tools/zentao/domain/repositories/zentao_team_members.dart
public protocol ZenTaoTeamMembers: Sendable {
    func productMembers(accountId: String, productId: String) async -> Outcome<[ProviderUser]>
    func executionMembers(accountId: String, executionId: String) async -> Outcome<[ProviderUser]>
}
