import AppKit
import CoreDomain
import CoreTools
import CoreUI
import Observation
import SwiftUI

/// Reactive snapshot of the DB-backed state the shell renders (Flutter: the stream providers in core/di/providers.dart) plus
/// the shell's own choices: which workspace is active, which account the chat shows, what is waiting to be connected.
/// Workspace switching and the launch behaviour live in `ShellModel+Workspaces.swift` / `ShellModel+Launch.swift`.
@MainActor @Observable
public final class ShellModel {
    public internal(set) var workspaces: [Workspace] = []
    public internal(set) var accounts: [Account] = []
    public private(set) var settings = AppSettings()
    /// The workspace the user joined (nil = the first one; a stale id falls back to it too). Remembered across launches.
    public internal(set) var activeWorkspaceId: String?
    /// Live sync status of every account (`auth expired` / `offline` / `error` feed the banners).
    public internal(set) var syncStatuses: [String: AccountSyncStatus] = [:]
    public let nav: AppNavController
    public let registry: ToolRegistry
    public let services: AppServices
    /// The ticket detail slide-over's state; the composition root fills `detail.extensions` (translation tab, editor route…).
    public let detail: DetailController
    /// App-wide toasts (`\.toasts` for everything under `AppShell`).
    public let toasts = AppToastController()
    /// The confetti-and-fireworks show `celebrate()` sets off over the whole window.
    public let celebration = CelebrationController()
    /// What the composition root puts into the shell (chat, mini apps, overview pages, editor, notifications…).
    public var host = ShellHost()
    /// The ZenTao account whose chat the Chat place shows; nil = the first one.
    public var chatAccountId: String?
    /// Asks the host to present the "Connect a tool" dialog (rail "+ Connect", overview buttons, "Re-authenticate").
    public var connectRequested = false
    /// Asks the host to present the "Create workspace" dialog (the switcher's footer).
    public var createWorkspaceRequested = false
    /// The quick-settings popover of the title bar's gear is open.
    public var quickSettingsOpen = false
    /// Asks the host to present the custom accent colour dialog (the quick-settings popover is a separate window, so the
    /// dialog is raised in the main one).
    public var customAccentRequested = false
    /// Asks the host to present the workspace editor (name, badge, colour, icon) for this workspace (the switcher's pencil).
    public var editWorkspaceRequested: Workspace?
    /// Bumped by the ⌘K command when no board is on screen; the title bar's search field takes focus when it changes.
    public var searchFocusTick = 0
    /// Bumped by ⌘N; the rail's "+" menu opens when it changes.
    public var newTicketMenuTick = 0
    /// Window-level dialogs (`.appDialog` registers here; `AppShell` draws them over everything).
    public let dialogs = DialogCenter()
    /// The key hints of the rail's places, up while ⌘ (or the modifiers of a chosen shortcut) is held.
    public let railHints = RailKeyHints()
    /// Last account opened per provider, so a rail section button of a tool whose sections sit on the rail reopens it
    /// (Flutter `railAccountMemoryProvider`).
    public var railAccountMemory: [ProviderType: String] = [:]
    /// Whether the chat opens by itself at launch (a ZenTao account is its login). Off in demo runs.
    @ObservationIgnored public var opensChatAtLaunch = true
    /// When the app last came to the front: a rail click that did that only shows its place (`railTap`).
    @ObservationIgnored public var activatedAt = Date.distantPast
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    /// The rail's right edge in the window, told by the rail itself: a click waiting left of it is another rail click.
    @ObservationIgnored public var railEdge: CGFloat = 0
    /// Keeps a place asked for from being built while the next rail click is already waiting (`railTap`).
    @ObservationIgnored public internal(set) lazy var railGate = CatchUpGate { [weak self] in
        guard let edge = self?.railEdge, edge > 0 else { return false }
        return ClickBacklog.hasClick { $0.x <= edge }
    }
    @ObservationIgnored let workspaceStore: ActiveWorkspaceStoring
    @ObservationIgnored var statusTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var knownAccountIds: Set<String>?
    @ObservationIgnored var loadedWorkspaces = false
    @ObservationIgnored var loadedAccounts = false
    @ObservationIgnored var chatLaunchPending = true
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(services: AppServices, registry: ToolRegistry, workspaceStore: ActiveWorkspaceStoring = NoActiveWorkspaceStore()) {
        self.services = services; self.registry = registry; self.workspaceStore = workspaceStore
        let accountsLookup = AccountLookup()
        let nav = AppNavController { id in accountsLookup.defaultSection(id) }
        self.nav = nav
        detail = DetailController(services: services, nav: nav, registry: registry)
        accountsLookup.model = { [weak self] in self }
        accountsLookup.registry = registry
        activeWorkspaceId = workspaceStore.load()
    }

    public func start() {
        guard tasks.isEmpty else { return }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                                    queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.activatedAt = Date() }
        }
        tasks = [
            Task { [weak self] in
                guard let s = self?.services.workspaces.watchWorkspaces() else { return }
                for await v in s { self?.workspaces = v; self?.loadedWorkspaces = true; self?.reconcile() }
            },
            Task { [weak self] in
                guard let s = self?.services.workspaces.watchAccounts() else { return }
                for await v in s { self?.accounts = v; self?.loadedAccounts = true; self?.accountsChanged(); self?.reconcile() }
            },
            Task { [weak self] in
                guard let s = self?.services.settings.watch() else { return }
                for await v in s { self?.settings = v }
            },
        ]
    }

    public func updateSettings(_ change: (inout AppSettings) -> Void) {
        var s = settings; change(&s); settings = s
        Task { _ = await services.settings.save(s) }
    }

    /// Sets off the celebration (a bug or task resolved). ZenTao views call it through `\.celebrate`.
    public func celebrate() { celebration.celebrate() }

    /// The newest chat message worth telling the user about, for the pet to say (`petShowsDetails`).
    public private(set) var petChatNews: PetChatNews?
    /// A new chat message came that the user is not looking at: the pet says what it says.
    public func announceChat(title: String, sender: String?, body: String, link: String? = nil) {
        petChatNews = PetChatNews(title: title, sender: sender, body: body, link: link, number: (petChatNews?.number ?? 0) + 1)
    }

    /// The newest news from an app on the rail, for the pet to say.
    public private(set) var petAppNews: PetAppNews?
    /// An app on the rail has news: the pet says so, and a click on it opens the app (`link`).
    public func announceApp(_ app: String, badge: String? = nil, title: String? = nil, body: String? = nil, link: String?) {
        petAppNews = PetAppNews(app: app, badge: badge, title: title, body: body, link: link, number: (petAppNews?.number ?? 0) + 1)
    }

    public func account(_ id: String) -> Account? { accounts.first { $0.id == id } }
    public func theme(systemIsDark: Bool) -> AppTheme { AppTheme(settings: settings, systemIsDark: systemIsDark) }

    // MARK: chat

    /// ZenTao accounts (each logs into its chat), in rail order — across every workspace.
    public var chatAccounts: [Account] { accounts.filter { $0.providerType == .zentao } }
    /// The account the Chat place shows: the chosen one, else the first.
    public var chatAccount: Account? {
        chatAccounts.first { $0.id == chatAccountId } ?? chatAccounts.first
    }
    /// A mini app is on screen (it replaces the nav pane and the viewport, like the Dart shell).
    public var miniAppOnScreen: Bool { nav.state.miniAppId != nil }
    /// The title bar's search has something to search here: tickets, or the place's own items (chat). A mini app (a web
    /// page with its own search), Settings and the ticket editor have none, so the field is not shown there.
    public var showsGlobalSearch: Bool {
        !miniAppOnScreen && nav.state.editor == nil && nav.state.rail != .settings
    }
}

/// Lets `AppNavController` (built before `self` exists) resolve a tool's default section for an account.
@MainActor private final class AccountLookup {
    var model: () -> ShellModel? = { nil }
    var registry: ToolRegistry?
    func defaultSection(_ accountId: String) -> SectionID {
        guard let a = model()?.account(accountId), let m = registry?.module(for: a.providerType) else { return "default" }
        return m.defaultSection
    }
}
