import AppKit
import CoreDomain
import CoreUI
import Foundation
import Observation

/// The shell's view-model: one account's connection status, chats, users and the open chat, fed by the repository's streams.
/// Ported from: lib/features/chat/presentation/providers/chat_providers.dart + chat_controller.dart
@MainActor @Observable
public final class ChatShellModel {
    public let accountId: String
    /// The signed-in ZenTao handle.
    public let selfAccount: String
    @ObservationIgnored let repository: ChatRepository
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var typingLapse: Task<Void, Never>?

    var status: ChatConnectionStatus?
    private(set) var conversations: [ChatConversation] = []
    private(set) var conversationsLoaded = false
    private(set) var users: [Int: ChatUser] = [:]
    private(set) var selfUserId: Int?
    private(set) var roleNames: [String: String] = [:]
    private(set) var typingRoster = TypingRoster()
    private(set) var selectedGid: String?
    /// The open chat's session; nil when none is selected or the chat is not known yet.
    private(set) var thread: ChatThreadSession?
    /// The chats kept open, least recently shown first: the one on screen (`thread`), the last few before it, and the
    /// ones built ahead of a visit (`warm`), which stay built behind it so going to one shows it at once. Only `thread`
    /// is on screen (`ChatThreadState.isOnScreen`).
    private(set) var openThreads: [ChatThreadSession] = []
    /// Opening a chat that is not kept builds its header, input and messages: three or four late frames, 150 ms in all
    /// on a real account. Eight covers the groups someone goes round in a working day.
    static let openThreadLimit = 8
    @ObservationIgnored var warming: Task<Void, Never>?
    /// Set by the view: a chat that has to be built is built a frame after its row lights up (see `select`).
    @ObservationIgnored var rowLightsFirst = false
    @ObservationIgnored private var showing: Task<Void, Never>?
    @ObservationIgnored private let clicks = ChatClickTiming()

    /// The list's tab, "unread only" and the picked categories (see `listFilter` for the one applied).
    var filter = ChatListFilter()
    var tab: ChatListTab {
        get { filter.tab }
        set { filter.tab = newValue }
    }
    private(set) var searchText = ""
    var highlightedGid: String?
    var searchPeriod: ChatSearchPeriod = .all
    /// Attachments the user opened that are still downloading.
    var downloading: Set<MessageContent> = []
    /// Opens a downloaded file or a link (wired to `ChatServices.openURL`).
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var showNewChat = false
    var showTrust = false
    var profileUserId: Int?
    /// The message the forward picker is open for.
    var forwardRequest: ChatForwardRequest?
    /// The user picked "Change group avatar" for this chat.
    var groupAvatarChat: ChatConversation?
    /// A group or category dialog that is open (see `ChatGroupDialog`).
    var groupDialog: ChatGroupDialog?
    var showCategoryManager = false
    /// The certificate already put to the user on this visit; asked once per fingerprint.
    private var askedFingerprint: String?
    let toasts = AppToastController()
    /// The host's line to the view (open-chat requests, the notification warning, profile link).
    let events: ChatShellEvents

    public init(accountId: String, selfAccount: String, repository: ChatRepository, events: ChatShellEvents? = nil) {
        self.accountId = accountId; self.selfAccount = selfAccount; self.repository = repository
        self.events = events ?? ChatShellEvents()
    }

    // MARK: derived

    var listed: [ListedChat] { ChatListing.visible(conversations, users: users, filter: listFilter, query: searchText) }
    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }
    func unread(_ tab: ChatListTab) -> Int { ChatListing.unread(conversations, tab: tab) }
    func typing(in gid: String) -> [Int] { typingRoster.typing(in: gid) }
    func chat(_ gid: String) -> ChatConversation? { conversations.first { $0.gid == gid } }
    var needsTrust: (host: String, fingerprint: String, subject: String, issuer: String)? {
        if case .needsTrust(let h, let f, let s, let i) = status { return (h, f, s, i) }
        return nil
    }

    // MARK: lifecycle

    func start() {
        guard tasks.isEmpty else { return }
        events.reportOpenChat(accountId: accountId, chatGid: selectedGid)
        let id = accountId, repo = repository
        tasks = [
            Task { [weak self] in for await s in repo.watchStatus(accountId: id) { self?.apply(status: s) } },
            Task { [weak self] in for await c in repo.watchConversations(accountId: id) { self?.apply(conversations: c) } },
            Task { [weak self] in for await u in repo.watchUsers(accountId: id) { self?.apply(users: u) } },
            Task { [weak self] in for await s in repo.watchSelfUserId(accountId: id) { self?.apply(selfUserId: s) } },
            Task { [weak self] in for await t in repo.watchTyping(accountId: id) { self?.apply(typing: t) } },
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }; tasks = []
        typingLapse?.cancel(); typingLapse = nil
        warming?.cancel(); warming = nil
        showing?.cancel(); showing = nil
        openThreads.forEach { $0.close() }; openThreads = []; thread = nil
        events.reportOpenChat(accountId: accountId, chatGid: nil)
    }

    // MARK: stream reducers

    func apply(status s: ChatConnectionStatus) {
        status = s
        if case .needsTrust(_, let fp, _, _) = s {
            if askedFingerprint != fp { askedFingerprint = fp; showTrust = true }
        } else {
            askedFingerprint = nil; showTrust = false
            if case .online = s, roleNames.isEmpty { Task { await loadRoleNames() } }
        }
    }

    func apply(conversations list: [ChatConversation]) {
        let first = !conversationsLoaded
        conversations = list; conversationsLoaded = true
        dropThreads { session in session !== thread && chat(session.state.chatGid) == nil }
        if let gid = selectedGid { syncThread(gid) }
        if first { scheduleWarming() }
    }

    func apply(users list: [ChatUser]) {
        users = Dictionary(list.map { ($0.userId, $0) }, uniquingKeysWith: { _, new in new })
        thread?.state.users = users
    }

    func apply(selfUserId id: Int?) {
        selfUserId = id
        thread?.state.selfUserId = id
    }

    func apply(typing signal: ChatTypingSignal, now: Date = Date()) {
        typingRoster = typingRoster.apply(signal, now: now, selfUserId: selfUserId)
        typingLapse?.cancel()
        guard let at = typingRoster.nextExpiry else { return }
        typingLapse = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.05, at.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.typingRoster = self?.typingRoster.prune(at) ?? TypingRoster()
        }
    }

    private func loadRoleNames() async {
        if case .success(let names) = await repository.roleNames(accountId: accountId) { roleNames = names; thread?.state.roleNames = names }
    }

    // MARK: selection

    /// A click on a chat of the list: answered at once, never held back for the click behind it. Clicked through faster
    /// than chats can be built, the ones overtaken are still not built - their row lights up and the click after it
    /// cancels the build (`select`).
    func tap(_ gid: String) { clicks.tapped(); select(gid) }

    func select(_ gid: String?) {
        guard gid != selectedGid else { return }
        selectedGid = gid
        events.reportOpenChat(accountId: accountId, chatGid: gid)
        showing?.cancel(); showing = nil
        // Building a chat holds its frame up, 60 ms and more: its row lights up in this frame and the chat is built in
        // the next, so the click is answered at once. A chat kept built is shown in the same frame as its row.
        if let gid, rowLightsFirst, !openThreads.contains(where: { $0.state.chatGid == gid }) {
            showing = Task { [weak self] in
                await NextDisplayFrame.wait()
                guard let self, !Task.isCancelled, selectedGid == gid else { return }
                show(gid)
            }
        } else {
            show(gid)
        }
        scheduleWarming()
    }

    private func show(_ gid: String?) {
        if thread?.state.chatGid != gid { thread?.hide(); thread = nil }
        if let gid { syncThread(gid) }
    }

    /// Builds `gid`'s chat behind the one on screen, ahead of a visit: unread, unplayed, and the first to go when room is
    /// needed. False when it is kept already, unknown, or there is no room.
    @discardableResult
    func warm(_ gid: String) -> Bool {
        guard openThreads.count < Self.openThreadLimit, let chat = chat(gid),
              !openThreads.contains(where: { $0.state.chatGid == gid }) else { return false }
        let session = makeSession(chat)
        session.state.isOnScreen = false
        openThreads.insert(session, at: 0)
        return true
    }

    private func makeSession(_ chat: ChatConversation) -> ChatThreadSession {
        let session = ChatThreadSession(accountId: accountId, chat: chat, selfAccount: selfAccount, repository: repository,
                                        period: { [weak self] in self?.searchPeriod ?? .all },
                                        onFailure: { [weak self] in self?.report($0) })
        session.state.users = users; session.state.selfUserId = selfUserId; session.state.roleNames = roleNames
        return session
    }

    /// Puts the selected chat's session on screen once its conversation is known — the one kept from an earlier visit, or
    /// a new one — and keeps its chat/users/self current.
    private func syncThread(_ gid: String) {
        guard let chat = chat(gid) else { return }
        if let thread, thread.state.chatGid == gid {
            if thread.state.chat != chat { thread.state.chat = chat }
            return
        }
        if let kept = openThreads.first(where: { $0.state.chatGid == gid }) {
            // What changed while it was behind another chat (only the chat on screen is kept current).
            let state = kept.state
            if state.chat != chat { state.chat = chat }
            if state.users != users { state.users = users }
            if state.selfUserId != selfUserId { state.selfUserId = selfUserId }
            if state.roleNames != roleNames { state.roleNames = roleNames }
            openThreads.removeAll { $0 === kept }; openThreads.append(kept)
            thread?.hide()
            thread = kept
            clicks.shown(kept.wasOpened ? "kept" : "built ahead")
            kept.show()
            return
        }
        let session = makeSession(chat)
        openThreads.append(session)
        thread?.hide()
        thread = session
        clicks.shown("built")
        session.open()
        // The least recently shown beyond the limit go (the new one is last, so never the chat on screen).
        let extra = openThreads.count - Self.openThreadLimit
        if extra > 0 { let oldest = Set(openThreads.prefix(extra).map(ObjectIdentifier.init)); dropThreads { oldest.contains(ObjectIdentifier($0)) } }
    }

    /// Closes the kept chats `gone` picks (the least recently shown beyond the limit, chats that no longer exist).
    private func dropThreads(_ gone: (ChatThreadSession) -> Bool) {
        let dropped = openThreads.filter(gone)
        guard !dropped.isEmpty else { return }
        dropped.forEach { $0.close() }
        openThreads.removeAll { session in dropped.contains { $0 === session } }
    }

    /// The search box's text; typing restarts the pick from the top.
    func setSearch(_ text: String) { searchText = text; highlightedGid = nil }

    func moveHighlight(_ step: Int) {
        guard isSearching else { return }
        highlightedGid = ChatListing.moved(highlightedGid, step: step, in: listed)
    }

    func openHighlighted() {
        guard isSearching, let gid = ChatListing.picked(highlightedGid, in: listed) else { return }
        select(gid)
    }

    // MARK: commands (use cases and CRUD pass-through)

    func report(_ f: Failure) {
        // Work given up because the user moved on (another chat opened) is not a failure to show.
        if case .cancelled = f { return }
        toasts.show(ChatShellLabels.failureText(f), kind: { if case .expired = f { .warning } else { .error } }())
    }
}
