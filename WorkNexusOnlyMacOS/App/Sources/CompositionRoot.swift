import AppKit
import CoreDomain
import CorePersistence
import CoreTools
import CoreUI
import FeatureAppUpdate
import FeatureChat
import FeatureConnections
import FeatureMiniApps
import FeatureNotifications
import FeaturePets
import FeatureTranslation
import FeatureWorkspaceOverview
import Foundation
import SharedKit
import ToolGitHub
import ToolGitLab
import ToolZenTao

/// The only place that knows both `data` and `domain` of every module (lib/app/di/service_locator.dart).
///
/// Order: database (every module's migration) -> repositories -> `SyncCoordinator` (with the adapter registry) -> ZenTao
/// wiring -> `AppServices` (+ the optional zentao hooks) -> `ToolRegistry` + `ShellModel` -> the tool modules (they need
/// the shell's nav) -> the features. `isDemo` (`WN_DEMO=1`, DEBUG builds) swaps in an in-memory credential store and
/// switches every network-facing background job off.
@MainActor
final class CompositionRoot {
    let isDemo: Bool
    let db: AppDatabase
    let credentials: CredentialStore
    let services: AppServices
    let registry: ToolRegistry
    let shell: ShellModel
    let coordinator: SyncCoordinator
    let liveSettings = LiveSettings()
    let notifier: DesktopNotifier
    let translation: TranslationFeature
    let connections: ConnectionsFeature
    let miniApps: MiniAppsFeature
    let update: UpdateModel
    let petLibrary: PetLibraryModel
    let petGallery: PetGalleryModel
    let overview: OverviewHolder
    let profiles: ZenTaoProfileRepository
    let ticketLinks: TicketLinkHandler
    let notifications: NotificationsModel?
    let chat: ChatWiring
    /// The local chat API for AI tools and the MCP setup guide.
    let aiTools: AiToolsWiring
    /// The "New todo" dialog any place of the app may ask for (a chat message → "Create todo").
    let todoPrompt: ZentaoTodoPrompt
    let platform: PlatformServices
    /// The diagnostics log; set up first so everything after it can report.
    let diagnostics: DiagnosticsWiring
    let autoUpdate: AutoUpdatePreference

    /// Own release identity: the Flutter app's releases ship `WorkNexus-macos-universal.zip` — never offer those to this app.
    static let updateConfig = AppUpdateConfig(appName: "WorkNexus Mac", githubOwner: "junNg0710", githubRepo: "WorkNexus",
                                              macAssetName: "WorkNexusMac-macos-universal.zip")

    init() throws {
        diagnostics = DiagnosticsWiring()
        let env = ProcessInfo.processInfo.environment
        isDemo = DemoMode.isEnabled
        let registrars = [ZentaoModuleData().migrations, ChatFeature.migrationRegistrar, MiniAppsFeature.migrationRegistrar]
        if let path = env["WN_DB_PATH"], !path.isEmpty {
            db = try AppDatabase.open(path: URL(fileURLWithPath: path), registrars: registrars)
        } else if DemoMode.isEnabled {
            db = try AppDatabase.inMemory(registrars: registrars)
        } else {
            db = try AppDatabase.open(registrars: registrars)
        }
        credentials = DemoMode.isEnabled ? MemoryCredentialStore() : KeychainCredentialStore()
        let workspaces = GRDBWorkspaceRepository(db: db)
        let tickets = GRDBTicketRepository(db: db, keepsLabel: { SyntheticLabels.isSynthetic($0) })
        let comments = GRDBCommentRepository(db: db), activity = GRDBActivityRepository(db: db)
        let syncStatus = GRDBSyncStatusRepository(db: db)
        let settingsRepo = GRDBSettingsRepository(db: db)

        // Sync: ONE adapter pool (ZenTao drops the previous session on every login).
        let coordinator = SyncCoordinator(tickets: tickets, workspaces: workspaces, comments: comments, activity: activity,
                                          credentials: credentials, registry: ProviderAdapterRegistryImpl(), statusRepository: syncStatus,
                                          listCache: SourceListCache(store: DatabaseSourceListStore(db: db)),
                                          detailWriter: DatabaseDetailWriter(db: db))
        self.coordinator = coordinator
        let wiring = ZentaoModuleData.wire(db: db, sync: coordinator, workspaces: workspaces, tickets: tickets, credentials: credentials,
                                           syncAssignedWork: { id in
            guard let account = await currentAccounts(workspaces).first(where: { $0.id == id }) else { return .failure(.notFound("No such account")) }
            return await coordinator.syncAccount(account)
        })
        let workflow = ZentaoModuleData.workflow(sync: coordinator, workspaces: workspaces, runner: CoordinatorRunner(coordinator))
        var services = AppServices(tickets: tickets, workspaces: workspaces, comments: comments, activity: activity,
                                   syncStatus: syncStatus, settings: settingsRepo, credentials: credentials,
                                   sync: coordinator, ticketDetail: coordinator, adapters: ProviderAdapterRegistryImpl())
        services.zentaoMessages = wiring.notifications; services.zentaoDashboard = wiring.dashboard
        services.zentaoEditor = wiring.editor; services.zentaoTeamMembers = wiring.teamMembers
        services.zentaoDrafts = wiring.drafts; services.zentaoTickets = wiring.tickets; services.zentaoWorkflow = workflow
        self.services = services

        // Shell + tool modules (modules need the shell's nav and the registry).
        let registry = ToolRegistry([])
        self.registry = registry
        let activeWorkspaceStore: ActiveWorkspaceStoring = DemoMode.isEnabled
            ? NoActiveWorkspaceStore()
            : FileActiveWorkspaceStore(file: PlatformPaths.applicationSupport().appendingPathComponent("active_workspace.txt"))
        let shell = ShellModel(services: services, registry: registry, workspaceStore: activeWorkspaceStore)
        shell.opensChatAtLaunch = !DemoMode.isEnabled
        self.shell = shell
        SavedFilterStorage.install(DatabaseSavedFilterRepository(db: db))
        ticketLinks = TicketLinkHandler(shell: shell)
        registry.register(ZentaoModule(ZentaoDependencies(wiring: wiring, workflow: workflow, services: services, nav: shell.nav,
                                                          registry: { registry })))
        let adapterOf: @Sendable (String) async -> ProviderAdapter? = { await coordinator.adapterFor($0) }
        let accountOf: @Sendable (String) async -> Account? = { id in await currentAccounts(workspaces).first { $0.id == id } }
        registry.register(GitlabModule(services: services, nav: shell.nav, registry: registry, mrService: GitLabMrServiceImpl(
            GitLabMrServiceDependencies(tickets: tickets, ticketDetail: coordinator, syncStatus: syncStatus, adapter: adapterOf, account: accountOf))))
        registry.register(GithubModule(services: services, nav: shell.nav, registry: registry, prService: GitHubPrServiceImpl(
            GitHubPrServiceDependencies(tickets: tickets, ticketDetail: coordinator, syncStatus: syncStatus, adapter: adapterOf, account: accountOf))))
        Task { await coordinator.setExtensions(Self.syncExtensions) }

        // Platform + features.
        let notifier = DesktopNotifier()
        self.notifier = notifier
        translation = TranslationFeature.make(database: db, credentials: credentials)
        let profiles = wiring.profiles
        self.profiles = profiles
        connections = ConnectionsFeature(services: services, db: db, afterAccountAdded: { account in
            if account.providerType == .zentao { _ = await profiles.refresh(account: account) }
        })
        let live = liveSettings
        miniApps = MiniAppsFeature.make(database: db, accounts: { await currentAccounts(workspaces) }, credentials: credentials,
                                        notifier: notifier,
                                        settings: MiniAppsSettings(liveLimit: { live.value.miniAppLiveLimit },
                                                                   notifyInBackground: { live.value.miniAppNotifyInBackground }),
                                        // The demo build keeps the saved passwords and session cookies in memory, like its credentials.
                                        secrets: DemoMode.isEnabled ? .inMemory() : .keychain)
        // Here rather than in `start()`: the session cookies kept from the last run must be on their way back into the web
        // view before the first mini app page can exist (a page waits for them), and `start()` runs after the first render.
        if !DemoMode.isEnabled { miniApps.startSessionCookies() }
        autoUpdate = MarkerFileAutoUpdatePreference(file: PlatformPaths.applicationSupport().appendingPathComponent("auto_update.txt"))
        update = AppUpdateFeature.makeModel(config: Self.updateConfig, preference: autoUpdate, quit: { DispatchQueue.main.async { AppQuit.now() } })
        // Pets from codex-pets.net live in Application Support; the demo build browses but keeps its own folder (`WN_SUPPORT_DIR`).
        let pets = PetsFeature.makeServices(root: PlatformPaths.applicationSupport().appendingPathComponent("pets", isDirectory: true))
        petLibrary = PetLibraryModel(services: pets)
        petGallery = PetGalleryModel(services: pets)
        overview = OverviewHolder(services: services, nav: shell.nav, registry: registry, workspaceId: shell.workspace?.id)
        platform = PlatformServices(isDemo: DemoMode.isEnabled)
        let todoPrompt = ZentaoTodoPrompt(todos: wiring.todos)
        todoPrompt.onCreated = { shell.toasts.show(appString("zentaoTodoCreated", "Todo created")) }
        self.todoPrompt = todoPrompt
        chat = ChatWiring(db: db, services: services, shell: shell, notifier: notifier, translation: translation, live: live,
                          todoPrompt: todoPrompt, isDemo: DemoMode.isEnabled)
        aiTools = AiToolsWiring(db: db, repository: chat.repository, isDemo: DemoMode.isEnabled)
        let bridge = chat.dockBadgeBridge
        let notificationsModel = NotificationsFeature.makeModel(
            services: services,
            hooks: NotificationsHooks(openTicket: { shell.nav.openTicket($0) }, toast: { shell.toasts.show($0, kind: $1) }),
            notifier: DemoMode.isEnabled ? nil : notifier, dockBadge: bridge, showDockBadge: true)
        notifications = notificationsModel
        // The editor and a mini app take the whole area beside the rail: the notifications panel closes under them.
        shell.nav.closeNotifications = { notificationsModel?.closePanel() }
        HostWiring(root: self).install()
    }

    /// Starts everything that runs for the life of the app (after the window exists).
    func start() async {
        diagnostics.follow(nav: shell.nav)
        shell.start()
        connections.model.start()
        overview.start()
        // The overview shows the active workspace: a switch gives it a model of its own.
        observeChanges({ [shell] in shell.workspace?.id }) { [overview] id in overview.follow(workspaceId: id) }
        overview.follow(workspaceId: shell.workspace?.id)
        miniApps.model.start()
        Task { for await s in services.settings.watch() { liveSettings.set(s); chat.apply(s); aiTools.apply(s) } }
        await seedWorkspaceIfEmpty()
        if isDemo {
            await DemoSeed.insert(services: services)
            DemoSeed.applyEnvironment(shell: shell)
            ChatSwitchBench.start(chat: chat)
            return
        }
        await coordinator.purgeAttachmentCache()
        platform.start(shell: shell)
        aiTools.start()
        update.start()
        notifications?.start()
        let accounts = await currentAccounts(services.workspaces)
        // The profile (real name) is what chat signs in with, so every saved ZenTao account refreshes it at launch, not only
        // when it is added (zentao_profile_startup.dart). Failures are not news: the next sync says the same.
        Task { [profiles] in
            for a in accounts where a.providerType == .zentao && a.credentialsRef != nil && a.baseUrl != nil {
                _ = await profiles.refresh(account: a)
            }
        }
        for account in accounts where account.credentialsRef != nil {
            Task { _ = await coordinator.syncAccount(account) }
        }
        await chat.start()
    }

    /// A fresh database starts with the personal workspace.
    private func seedWorkspaceIfEmpty() async {
        var it = services.workspaces.watchWorkspaces().makeAsyncIterator()
        if let existing = await it.next(), existing.isEmpty {
            _ = await services.workspaces.createWorkspace(Workspace(id: "default", name: "My Workspace", shortCode: "MW",
                                                                   colorValue: 0xFF5A57D6, isPersonal: true))
        }
    }

    /// GitLab / GitHub reviewers and member lists for `SyncCoordinator` (the shared layer cannot know the tools).
    static let syncExtensions = SyncExtensions(
        setReviewers: { adapter, ticket, logins in
            if let a = adapter as? GitLabMrAdapter { return (await a.setReviewers(ticket, logins: logins)).map { _ in () } }
            if let a = adapter as? GitHubPrAdapter { return (await a.setReviewers(ticket, logins: logins)).map { _ in () } }
            return nil
        },
        listUsers: { adapter, ticket in
            if let a = adapter as? GitLabMrAdapter { return await a.listProjectMembers(ticket) }
            if let a = adapter as? GitHubPrAdapter { return await a.listRepoAssignees(ticket) }
            return nil
        })
}

/// `SyncCoordinator.runOptimisticAction` as the ZenTao workflow's runner.
struct CoordinatorRunner: ZenTaoOptimisticRunner {
    let coordinator: SyncCoordinator
    init(_ c: SyncCoordinator) { coordinator = c }
    func runOptimisticAction(_ original: Ticket, _ optimistic: Ticket,
                             _ action: @escaping @Sendable () async -> Outcome<Void>) async -> Outcome<Void> {
        await coordinator.runOptimisticAction(original, optimistic: optimistic) { await action() }
    }
}
