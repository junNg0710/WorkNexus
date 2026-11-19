import CoreDomain
import Foundation
import Observation

/// What the panic switch is built from; the composition root fills it.
public struct PanicSwitchDependencies {
    public var repository: PanicSwitchConfigRepository
    public var chats: PanicChatGateway
    public var apps: AppSwitcher
    public var overlay: PanicOverlay
    public var sticker: PanicStickerSource
    /// The accounts, again each time they change.
    public var accounts: @Sendable () -> AsyncStream<[Account]>

    public init(repository: PanicSwitchConfigRepository, chats: PanicChatGateway, apps: AppSwitcher, overlay: PanicOverlay,
                sticker: PanicStickerSource, accounts: @escaping @Sendable () -> AsyncStream<[Account]>) {
        self.repository = repository; self.chats = chats; self.apps = apps; self.overlay = overlay; self.sticker = sticker
        self.accounts = accounts
    }
}

/// Ported from: lib/features/panic_switch/presentation/providers/{panic_switch_config_controller,panic_switch_providers}.dart
/// and presentation/widgets/panic_switch_listener.dart — the panic switch for the whole app: the account it works
/// through, its settings (as Settings edits them), the sticker listener, the floating button, and what the settings card
/// lists (chats, members, apps).
@MainActor @Observable
public final class PanicSwitchModel {
    public enum Members: Equatable { case idle, loading, loaded([PanicPerson]), failed }
    public enum Apps: Equatable { case loading, loaded([AppRef]), failed }

    /// The ZenTao account the switch works through; nil keeps the feature off (and its settings card away).
    public private(set) var account: Account?
    public private(set) var config: PanicSwitchConfig?
    public private(set) var loadFailed = false
    /// The chats the sticker can go to, while the settings card watches them (`watchChats`).
    public private(set) var chats: [PanicChat] = []
    public private(set) var members: Members = .idle
    public private(set) var apps: Apps = .loading

    @ObservationIgnored public private(set) var runtime: PanicSwitchRuntime!
    @ObservationIgnored private let deps: PanicSwitchDependencies
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var defaultGroupTask: Task<Void, Never>?
    @ObservationIgnored private var chatRefs: [PanicChatRef]?
    @ObservationIgnored private var people: [Int: PanicPerson] = [:]

    public init(_ deps: PanicSwitchDependencies) {
        self.deps = deps
        runtime = PanicSwitchRuntime(account: { [weak self] in self?.account }, config: { [weak self] in self?.config },
                                     run: RunPanicSwitch(deps.apps), send: SendPanicSticker(deps.chats, deps.sticker))
    }

    /// Whether three clicks on the pet send the alert: wanted (`overlayVisible`, the setting the Flutter app keeps for its
    /// floating button), with a chat to send to, for a user of the ZenTao the feature is offered for.
    public var overlayVisible: Bool { account != nil && config?.overlayVisible == true && config?.sendChatGid != nil }

    /// The gesture on the pet that raises the alert now; nil while the alert is off.
    public var petGesture: PanicPetGesture? { overlayVisible ? config?.petGesture ?? .hold : nil }

    /// The pet's alert gesture: sends the sticker and, once it is sent, switches apps here too (see
    /// `PanicSwitchRuntime.onAlert`).
    public func petAlert() {
        guard overlayVisible else { return }
        Task { report(await runtime.onAlert()) }
    }

    /// Loads the settings, follows the accounts, listens for the sticker and puts the floating button up. Runs for the life
    /// of the app (also while the window is hidden).
    public func start() {
        guard tasks.isEmpty else { return }
        let accounts = deps.accounts
        tasks.append(Task { [weak self] in
            await self?.loadConfig()
            for await list in accounts() { self?.setAccount(FindPanicSwitchAccount()(list)) }
        })
        // Every live message passes here: only a sticker under the reserved name (a string compare, off the main thread)
        // goes on to the rest of the checks.
        let incoming = deps.chats.incoming()
        tasks.append(Task.detached { [weak self] in
            for await message in incoming where ShouldTriggerPanic.isPanicSticker(message) {
                await self?.received(message)
            }
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }; tasks = []
        defaultGroupTask?.cancel(); defaultGroupTask = nil
        deps.overlay.hide()
    }

    /// Saves `change` applied to the current settings; when it cannot be saved nothing changes and the failure is returned
    /// for the card to say so.
    @discardableResult
    public func edit(_ change: (inout PanicSwitchConfig) -> Void) async -> Outcome<Void> {
        guard let current = config else { return .success(()) }
        var next = current
        change(&next)
        guard next != current else { return .success(()) }
        let saved = await deps.repository.save(next)
        if case .success = saved {
            config = next
            configChanged(from: current)
        }
        return saved
    }

    /// Switches apps now, as the sticker would, without any chat ("Try").
    public func tryNow() async -> Outcome<Void> { await runtime.runNow() }

    /// Keeps `chats` in step with the account's chats and people until the caller is cancelled (the card's `.task`).
    public func watchChats(selfTitle: String) async {
        guard let accountId = account?.id else { return }
        let conversations = deps.chats.conversations(accountId: accountId), users = deps.chats.users(accountId: accountId)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                for await list in conversations { self?.chatRefs = list; self?.rebuildChats(selfTitle) }
            }
            group.addTask { @MainActor [weak self] in
                for await list in users {
                    self?.people = Dictionary(list.map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a })
                    self?.rebuildChats(selfTitle)
                }
            }
        }
    }

    /// The members of the chat listened in who could send the sticker.
    public func loadMembers() async {
        guard let accountId = account?.id, let config, let chatGid = config.receiveChatGid, !config.sendsToSelf else {
            members = .idle; return
        }
        members = .loading
        switch await LoadPanicGroupMembers(deps.chats)(accountId: accountId, chatGid: chatGid) {
        case .success(let people): members = .loaded(people)
        case .failure(let f): members = .failed; report(.failure(f))
        }
    }

    /// The apps on this Mac to pick from (read again each time the card opens).
    public func loadApps() async {
        switch await deps.apps.listApps() {
        case .success(let list): apps = .loaded(list)
        case .failure(let f): apps = .failed; report(.failure(f))
        }
    }

    // MARK: private

    private func loadConfig() async {
        switch await deps.repository.load() {
        case .success(let c): config = c; loadFailed = false
        case .failure(let f): loadFailed = true; report(.failure(f))
        }
        ensureDefaultGroup()
    }

    private func setAccount(_ next: Account?) {
        guard next != account else { return }
        account = next
        chats = []; chatRefs = nil; people = [:]; members = .idle
        ensureDefaultGroup()
    }

    private func configChanged(from old: PanicSwitchConfig) {
        guard let config else { return }
        if config.chatGid == nil { ensureDefaultGroup() }
    }

    /// Until a group is picked, use the team's group once it is known; then stop watching the chats.
    private func ensureDefaultGroup() {
        defaultGroupTask?.cancel(); defaultGroupTask = nil
        guard let accountId = account?.id, let config, config.chatGid == nil else { return }
        let conversations = deps.chats.conversations(accountId: accountId)
        defaultGroupTask = Task { [weak self] in
            for await list in conversations {
                guard let gid = PickDefaultPanicGroup()(list) else { continue }
                await self?.edit { if $0.chatGid == nil { $0.chatGid = gid } }
                return
            }
        }
    }

    private func received(_ message: PanicIncomingMessage) async {
        report(await runtime.onIncoming(message))
    }

    private func rebuildChats(_ selfTitle: String) {
        guard let chatRefs else { return }
        chats = ListPanicChats()(chatRefs, people, selfTitle: selfTitle)
    }

    /// Both the listener and the button run in the background, with nobody looking at a screen to tell; the log is where a
    /// failure is seen.
    private func report(_ result: Outcome<Void>) {
        if case .failure(let f) = result { Diagnostics.warning("panic", "Panic switch: \(f.message)") }
    }
}
