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

    var tab: ChatListTab = .all
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

    var listed: [ListedChat] { ChatListing.visible(conversations, users: users, tab: tab, query: searchText) }
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
        thread?.close(); thread = nil
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
        conversations = list; conversationsLoaded = true
        if let gid = selectedGid { syncThread(gid) }
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
        if case .success(let names) = await repository.roleNames(accountId: accountId) { roleNames = names }
    }

    // MARK: selection

    func select(_ gid: String?) {
        guard gid != selectedGid else { return }
        thread?.close(); thread = nil
        selectedGid = gid
        events.reportOpenChat(accountId: accountId, chatGid: gid)
        if let gid { syncThread(gid) }
    }

    /// Creates the open chat's session once its conversation is known, and keeps its chat/users/self current.
    private func syncThread(_ gid: String) {
        guard let chat = chat(gid) else { return }
        if let thread, thread.state.chatGid == gid {
            if thread.state.chat != chat { thread.state.chat = chat }
            return
        }
        let session = ChatThreadSession(accountId: accountId, chat: chat, selfAccount: selfAccount, repository: repository,
                                        period: { [weak self] in self?.searchPeriod ?? .all },
                                        onFailure: { [weak self] in self?.report($0) })
        session.state.users = users; session.state.selfUserId = selfUserId
        thread = session
        session.open()
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

    func connect() { Task { if case .failure(let f) = await ConnectChat(repository)(accountId) { report(f) } } }

    /// Trusts the pending certificate; returns the failure's text for the dialog to show.
    func trust(fingerprint: String) async -> String? {
        switch await TrustChatCertificate(repository)(accountId: accountId, fingerprint: fingerprint) {
        case .success: showTrust = false; return nil
        case .failure(let f): return ChatShellLabels.failureText(f)
        }
    }

    /// Opens (creating on first use) the one-to-one chat with `userId` and selects it.
    @discardableResult
    func openDirectChat(userId: Int) async -> Bool {
        switch await OpenDirectChat(repository)(accountId: accountId, userId: userId) {
        case .success(let gid): tab = .all; setSearch(""); select(gid); return true
        case .failure(let f): report(f); return false
        }
    }

    func createGroup(name: String, memberIds: [Int]) async -> Bool {
        switch await CreateGroupChat(repository)(accountId: accountId, name: name, memberIds: memberIds) {
        case .success(let gid): tab = .all; setSearch(""); select(gid); return true
        case .failure(let f): report(f); return false
        }
    }

    func setStarred(_ chat: ChatConversation, _ starred: Bool) {
        Task { if case .failure(let f) = await repository.setChatStarred(accountId: accountId, chatGid: chat.gid, starred: starred) { report(f) } }
    }

    func setMuted(_ chat: ChatConversation, _ muted: Bool) {
        Task { if case .failure(let f) = await repository.setChatMuted(accountId: accountId, chatGid: chat.gid, muted: muted) { report(f) } }
    }

    /// Forwards each message (in the order given) to each chat; reports the first failure. True when every chat got all.
    func forward(_ messages: [ChatMessage], to chatGids: [String]) async -> Bool {
        var first: Failure?
        for message in messages {
            if case .failure(let f) = await ForwardChatMessage(repository)(message, toChatGids: chatGids) { first = first ?? f }
        }
        if let first { report(first); return false }
        return true
    }

    func setPresence(_ p: ChatPresence) {
        Task { if case .failure(let f) = await repository.setMyPresence(accountId: accountId, presence: p) { report(f) } }
    }
}
