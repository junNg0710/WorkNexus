import AppKit
import CoreDomain
import Foundation
import Observation

/// Everything one open conversation needs beyond the shared `ChatThreadState`: its search, history download, member count
/// and the open/mark-read behaviour. Created by `ChatShellModel` when a chat is selected, dropped when it closes.
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
    /// A group's member ids; nil until loaded.
    private(set) var memberIds: [Int]?
    private(set) var membersFailed = false

    @ObservationIgnored private let repository: ChatRepository
    @ObservationIgnored private let onFailure: (Failure) -> Void
    @ObservationIgnored private let isAppActive: @MainActor () -> Bool
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var markingRead = false
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

    var canSend: Bool { CanSendToChat()(state.chat, selfUserId: state.selfUserId, selfAccount: state.selfAccount) }
    var canPin: Bool { PinChatMessage(repository).canPin(state.chat, selfUserId: state.selfUserId, selfAccount: state.selfAccount) }

    /// Pulls the newest page, marks the chat read and counts the members.
    func open() {
        let gid = state.chatGid, id = state.accountId
        // What was unread before opening marks it read, for the AI catch-up.
        assistant.opened(unread: state.chat.unreadCount)
        tasks.append(Task { [weak self] in
            guard let self else { return }
            if case .success(let n) = await repository.memberCount(accountId: id, chatGid: gid), state.chat.type != .one2one { memberCount = n }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            let repository = repository
            let refreshed = await PerformanceLog.measure("chat: open (refresh newest messages)", slowerThan: 0.5) {
                await RefreshChatMessages(repository)(accountId: id, chatGid: gid)
            }
            if case .failure(let f) = refreshed { onFailure(f); return }
            await markRead()
        })
    }

    /// Marks the chat read when new messages arrive while it is open and the app is in front.
    func unreadChanged(_ unread: Int) {
        guard unread > 0, unread != lastUnreadMarked, isAppActive() else { return }
        Task { await markRead() }
    }

    private func markRead() async {
        guard !markingRead else { return }
        markingRead = true; defer { markingRead = false }
        lastUnreadMarked = state.chat.unreadCount
        if case .failure(let f) = await MarkChatRead(repository)(accountId: state.accountId, chatGid: state.chatGid) { onFailure(f) }
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
        search.cancel(); history.teardown()
    }
}
