/// Ported from: lib/tools/zentao/zentao_module.dart (data/domain wiring only)
import CoreDomain
import CorePersistence
import Foundation

/// The single documented entry type of the ZenTao tool's Domain + Data layers. The composition root (`App/`)
/// and the ToolZenTao Presentation pass wire everything through these entry points; nothing registers itself.
///
/// ### Database
/// - `ZenTaoMigrations.registrar` - tables `zenTaoProfiles`, `dashboardSnapshots`, `sourceListSnapshots`,
///   `zenTaoDocSnapshots`, `zenTaoNotifications`, `ticketDrafts` (migration id `zentao_v1`); pass it to
///   `AppDatabase.open(registrars:)`.
///
/// ### Provider adapter
/// - `ZentaoAdapterFactory.makeAdapter(account:secret:)` -> `ProviderAdapter` (a `ZenTaoProviderAdapter`, which also
///   conforms to `ZenTaoMessagesAdapter`; `listTaskBugs` is ZenTao-specific).
/// - `ZenTaoClient` - the transport (REST v1 + classic channel); one per account, shared through `ZenTaoClientProvider`.
/// - `PooledZenTaoAdapters` (+ `WorkspaceZenTaoAccountLookup`) adapt the core `AccountSyncService` pool to
///   `ZenTaoClientProvider` / `ZenTaoAdapterProvider`.
///
/// ### Services the UI uses (protocols in Domain, implementations in Data)
/// - `ZenTaoWorkflowService` <- `ZenTaoWorkflowActions(runner:adapters:clients:)` (bug confirm / resolve / activate /
///   close, task actions with `ZenTaoTaskActionInput`; needs a `ZenTaoOptimisticRunner` from the sync layer).
/// - `ZenTaoTicketEditor` <- `ZenTaoTicketEditorService(clients:tickets:)` (bug / task forms, options, save, image upload).
/// - `ZenTaoTeamMembers` <- `ClassicZenTaoTeamMembers(clients:)`.
/// - `ZenTaoModuleEditor` <- `ClassicZenTaoModuleEditor(clients:)` (adds a module to a board's tree).
/// - `ZenTaoTodos` <- `ZenTaoTodoService(clients:)` (a personal todo, e.g. made from a chat message).
/// - `ZenTaoTicketService` / `ZenTaoViewPages` / `ZenTaoTaskBugs` <- `ZenTaoTicketServiceImpl(accounts:adapters:tickets:cache:)`.
/// - `ZenTaoProfileRepository` <- `GRDBZenTaoProfileRepository`; `ZenTaoDocRepository` <- `GRDBZenTaoDocRepository`;
///   `ZenTaoNotificationRepository` <- `GRDBZenTaoNotificationRepository`; `ZenTaoDashboardRepository` <-
///   `GRDBZenTaoDashboardRepository`; `ZenTaoTicketDraftRepository` <- `GRDBZenTaoTicketDraftRepository`;
///   `ZenTaoSourceListCache` <- `GRDBZenTaoSourceListCache`.
///
/// ### Pure domain helpers
/// `ExportZenTaoDoc` (via `ZentaoModuleData.exportDoc`), `renderZenTaoDocHtml`, `ListZenTaoBugActions`, `ListZenTaoTaskActions`, `ListZenTaoCreateActions`, `CheckZenTaoTaskInput`,
/// `CheckZenTaoAssignLeft`, `SummarizeTaskEffort`, `BuildZenTaoModuleTree`, `ListTaskBugs`, `IsDueThisWeek`,
/// `ZenTaoProductTree` / `ZenTaoProjectTree`, `zentaoBugColumnFor` / `zentaoTaskColumnFor` / `zentaoStatusOf` /
/// `zentaoModuleOf`, `ZenTaoBugStream` / `ZenTaoBugBrowseType`, label helpers (`zentaoSeverityLabel`, ...).
public struct ZentaoModuleData: Sendable {
    public let migrations: MigrationRegistrar
    public init() { migrations = ZenTaoMigrations.registrar }

    /// Everything the composition root needs to build one ZenTao account's stack on top of an open database.
    public struct Wiring: Sendable {
        public let profiles: ZenTaoProfileRepository
        public let docs: ZenTaoDocRepository
        public let drafts: ZenTaoTicketDraftRepository
        public let sourceLists: ZenTaoSourceListCache
        public let notifications: ZenTaoNotificationRepository
        public let dashboard: ZenTaoDashboardRepository
        public let tickets: ZenTaoTicketServiceImpl
        public let editor: ZenTaoTicketEditor
        public let teamMembers: ZenTaoTeamMembers
        public let teamGroups: ZenTaoTeamGroupRepository
        public let todos: ZenTaoTodos
        public let pinnedPeople: ZenTaoPinnedPeopleStore
        public let boardScopes: ZenTaoBoardScopeStore
        public let recentAssignees: ZenTaoRecentAssigneesStore
        public let departmentTeams: ZenTaoDepartmentTeamSource
        public let pinnedTeams: ZenTaoPinnedTeamsStore
        public let modules: ZenTaoModuleEditor
    }

    /// Wires the Data layer over `db` and the core services. `runner` is the sync layer's optimistic-action runner
    /// (used by `workflow(runner:)`). `syncAssignedWork` pulls every ticket assigned to an account into the store.
    public static func wire(db: AppDatabase, sync: AccountSyncService, workspaces: WorkspaceRepository, tickets: TicketRepository,
                            credentials: CredentialStore,
                            syncAssignedWork: @escaping ZenTaoAssignedWorkSyncer = { _ in .success(0) }) -> Wiring {
        let lookup = WorkspaceZenTaoAccountLookup(workspaces)
        let pool = PooledZenTaoAdapters(sync: sync, accounts: lookup)
        let cache = GRDBZenTaoSourceListCache(db: db)
        let service = ZenTaoTicketServiceImpl(accounts: lookup, adapters: pool, tickets: tickets, cache: cache)
        let docRemote: ZenTaoDocsRemoteFactory = { account in await pool.zenTaoClient(accountId: account.id) }
        return Wiring(
            profiles: GRDBZenTaoProfileRepository(db: db, credentials: credentials),
            docs: GRDBZenTaoDocRepository(db: db, remote: docRemote),
            drafts: GRDBZenTaoTicketDraftRepository(db: db),
            sourceLists: cache,
            notifications: GRDBZenTaoNotificationRepository(
                db: db, fetch: { await service.fetchZenTaoMessages(accountId: $0) },
                run: { await service.zenTaoMessageAction(accountId: $0, action: $1) }),
            dashboard: GRDBZenTaoDashboardRepository(
                db: db, fetch: { await service.fetchZenTaoUserInfo(accountId: $0, fields: $1, limit: $2) },
                syncAssigned: syncAssignedWork),
            tickets: service,
            editor: ZenTaoTicketEditorService(clients: pool, tickets: service),
            teamMembers: ClassicZenTaoTeamMembers(clients: pool),
            teamGroups: GRDBZenTaoTeamGroupRepository(db: db),
            todos: ZenTaoTodoService(clients: pool),
            pinnedPeople: UserDefaultsZenTaoPinnedPeople(),
            boardScopes: UserDefaultsZenTaoBoardScopes(),
            recentAssignees: UserDefaultsZenTaoRecentAssignees(),
            departmentTeams: RestZenTaoDepartmentTeams(clients: pool),
            pinnedTeams: UserDefaultsZenTaoPinnedTeams(),
            modules: ClassicZenTaoModuleEditor(clients: pool))
    }

    /// The document export use case with the real HTML-to-Markdown converter.
    public static func exportDoc(_ docs: ZenTaoDocRepository) -> ExportZenTaoDoc {
        ExportZenTaoDoc(docs, markdown: { ZenTaoDocMarkdown.render($0) })
    }

    /// The workflow service over the same adapter pool.
    public static func workflow(sync: AccountSyncService, workspaces: WorkspaceRepository,
                                runner: ZenTaoOptimisticRunner) -> ZenTaoWorkflowService {
        let pool = PooledZenTaoAdapters(sync: sync, accounts: WorkspaceZenTaoAccountLookup(workspaces))
        return ZenTaoWorkflowActions(runner: runner, adapters: pool, clients: pool)
    }
}
