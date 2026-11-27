import AppKit
import CoreDomain
import Foundation
import Observation

/// Everything one open conversation needs beyond the shared `ChatThreadState`: its search, history download, member count
/// and the open/mark-read behaviour. Created by `ChatShellModel` when a chat is selected; kept while the chat is one of
/// the last few opened (`hide()` / `show()`), closed when it is dropped.
/// Ported from: lib/features/chat/presentation/widgets/thread_pane.dart
@MainActor @Observable
final class ChatThreadSession {
    let state: ChatThreadState
    let search: ChatThreadSearch
    let history: ChatHistoryDownloadModel
    /// The AI assistant of this visit (the catch-up offer, the summary panel's scope).
    let assistant: ChatAssistantModel
    /// Kept once known, so "N members" does not blink out when the chat reopens.
    private(set) var memberCount: Int?
    /// The chat's image and file messages stored locally, newest first; nil until the first read.
    private(set) var attachments: [ChatMessage]?
    /// The names of the stickers this Mac knows: a picture named like one, at sticker size, is a sticker.
    private(set) var stickerNames: Set<String> = []
    /// The chat's photos and videos, and its files; nil until loaded. Stickers are left out of both.
    var shared: (media: [ChatMessage], files: [ChatMessage])? {
        attachments.map { ChatShellLabels.splitAttachments($0, stickerNames: stickerNames) }
    }
    /// A group's member ids; nil until loaded.
    private(set) var memberIds: [Int]?
    private(set) var membersFailed = false

    @ObservationIgnored private let repository: ChatRepository
    @ObservationIgnored private let onFailure: (Failure) -> Void
    @ObservationIgnored private let isAppActive: @MainActor () -> Bool
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var markingRead = false
    /// `open()` has run: false for a chat built ahead of its first visit (`ChatShellModel.warm`).
    @ObservationIgnored private var opened = false
    var wasOpened: Bool { opened }
    @ObservationIgnored private var lastUnreadMarked = 0

    init(accountId: String, chat: ChatConversation, selfAccount: String?, repository: ChatRepository,
         period: @escaping () -> ChatSearchPeriod, onFailure: @escaping (Failure) -> Void,
         isAppActive: @escaping @MainActor () -> Bool = { NSApp?.isActive ?? true }) {
        state = ChatThreadState(accountId: accountId, chat: chat, selfAccount: selfAccount)
        search = ChatThreadSearch(accountId: accountId, chatGid: chat.gid, repository: repository, period: period)
        history = ChatHistoryDownloadModel(accountId: accountId, chatGid: chat.gid, repository: repository, period: period)
        assistant = ChatAssistantModel(accountId: accountId, chatGid: chat.gid)
        self.repository = repository; self.onFailure = onFailure; self.isAppActive = isAppActive
        let state = state
        search.onQuery = { state.searchQuery = $0 }
        search.onJump = { state.requestJump(to: $0) }
        history.onProgress = { [weak search] in search?.reload() }
    }

    /// Reads the known stickers' names, for `shared`.
    func loadStickerNames(_ stickers: StickerRepository?) async {
        if case .success(let known)? = await stickers?.stickers() { stickerNames = Set(known.map(\.name)) }
    }

    /// One session, one pane: a chat closed and opened again is built anew.
    nonisolated var identity: ObjectIdentifier { ObjectIdentifier(self) }
    /// The key of this session's pane among the kept ones (`KeptHosts`): a chat closed and opened again gets a new pane.
    let hostKey = UUID().uuidString

    var canSend: Bool { CanSendToChat()(state.chat, selfUserId: state.selfUserId, selfAccount: state.selfAccount) }
    var canPin: Bool { PinChatMessage(repository).canPin(state.chat, selfUserId: state.selfUserId, selfAccount: state.selfAccount) }

    /// Pulls the newest page, marks the chat read and counts the members.
    func open() {
        opened = true
        let gid = state.chatGid, id = state.accountId
        // What was unread before opening marks it read, for the AI catch-up.
        assistant.opened(unread: state.chat.unreadCount)
        tasks.append(Task { [weak self] in
            guard let self else { return }
            if case .success(let n) = await repository.memberCount(accountId: id, chatGid: gid), state.chat.type != .one2one { memberCount = n }
        })
        refresh(thenMarkRead: true)
    }

    /// Another chat takes the screen and this one stays open behind it: nothing in it is read or played until `show()`.
    func hide() {
        guard state.isOnScreen else { return }
        state.isOnScreen = false
        state.video.stop()
    }

    /// Back on screen after `hide()`: pulls what a reconnect may have missed. The message list goes to its newest message
    /// and marks the chat read once that is in view.
    func show() {
        guard !state.isOnScreen else { return }
        // Built ahead of its first visit: this is the visit that opens it.
        guard opened else { state.isOnScreen = true; open(); return }
        assistant.catchUpDismissed = false
        assistant.opened(unread: state.chat.unreadCount)
        state.isOnScreen = true
        refresh(thenMarkRead: false)
    }

    private func refresh(thenMarkRead: Bool) {
        let gid = state.chatGid, id = state.accountId
        refreshing?.cancel()
        refreshing = Task { [weak self] in
            guard let self else { return }
            let repository = repository
            let refreshed = await PerformanceLog.measure("chat: open (refresh newest messages)", slowerThan: 0.5) {
                await RefreshChatMessages(repository)(accountId: id, chatGid: gid)
            }
            guard !Task.isCancelled else { return }
            if case .failure(let f) = refreshed { BackgroundChatFailure.handle(f, while: "refreshing an opened chat", notify: onFailure); return }
            if thenMarkRead, state.isOnScreen { await markRead() }
        }
    }

    /// Marks the chat read when new messages arrive while it is on screen and the app is in front.
    func unreadChanged(_ unread: Int) {
        guard state.isOnScreen, unread > 0, unread != lastUnreadMarked, isAppActive() else { return }
        Task { await markRead() }
    }

    private func markRead() async {
        guard !markingRead else { return }
        markingRead = true; defer { markingRead = false }
        lastUnreadMarked = state.chat.unreadCount
        if case .failure(let f) = await MarkChatRead(repository)(accountId: state.accountId, chatGid: state.chatGid) {
            BackgroundChatFailure.handle(f, while: "marking a chat read", notify: onFailure)
        }
    }

    func watchAttachments() async {
        for await list in repository.watchAttachments(accountId: state.accountId, chatGid: state.chatGid) { attachments = list }
    }

    func loadMembers() async {
        membersFailed = false
        switch await repository.members(accountId: state.accountId, chatGid: state.chatGid) {
        case .success(let ids): memberIds = ids
        case .failure: membersFailed = true
        }
    }

    /// Loads the members again after people were added or removed, with the count shown in the info.
    func reloadMembers() async {
        await loadMembers()
        if let ids = memberIds { memberCount = ids.count }
    }

    /// Opens the search bar (also when another slice asks for it with `sidePanel = .search`).
    func toggleSearch() {
        if search.isOpen { search.close(); history.teardown() } else { search.isOpen = true }
    }

    func close() {
        tasks.forEach { $0.cancel() }; tasks = []
        refreshing?.cancel(); refreshing = nil
        search.cancel(); history.teardown()
    }
}
