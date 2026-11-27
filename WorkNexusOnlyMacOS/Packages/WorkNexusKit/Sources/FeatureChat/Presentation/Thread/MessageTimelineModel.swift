/// Ported from: lib/features/chat/presentation/widgets/message_list.dart (_MessageListState) + providers/chat_providers.dart
/// (chatMessagesProvider, chatRepliesProvider, chatReactionsProvider, chatThreadSummariesProvider)
import CoreDomain
import Foundation
import Observation
import SwiftUI

/// A request for the list to scroll somewhere; `token` makes repeated requests to the same place fire again.
struct ChatScrollRequest: Equatable {
    enum Target: Equatable { case bottom, message(gid: String) }
    var target: Target
    var animated = true
    var token = UUID()

    /// Whether the list glides there. A jumped-to message already on screen glides; one off screen (far up, or in a window
    /// just loaded around it) appears centred at once — an animated trip through rows not laid out yet showed the rows in
    /// between, then a correction once they were measured.
    /// Ported from: lib/features/chat/presentation/widgets/message_jump.dart (a row already laid out glides, others appear)
    func animates(onScreen: Set<String>) -> Bool {
        guard animated else { return false }
        if case .message(let gid) = target { return onScreen.contains(gid) }
        return true
    }
}

/// The windowed timeline one open conversation shows: the messages in the current window (newest page, or a stretch
/// around a message jumped to), the reactions and reply threads built from the chat's replies, who is typing, and the
/// paging state. The view reads it; the paging and jump logic is in the extensions. Local-first: everything comes from
/// the repository's watch streams, never straight from the network.
@MainActor @Observable
final class MessageTimelineModel {
    let state: ChatThreadState
    let services: ChatServices
    var accountId: String { state.accountId }
    var chatGid: String { state.chatGid }

    // MARK: what is shown
    private(set) var messages: [ChatMessage] = []
    /// Set once the first page has been read, so an empty chat reads as empty and not as still loading.
    private(set) var loaded = false
    var window = ChatMessageWindow.initial { didSet { if window != oldValue { windowEvents.yield(window) } } }
    private(set) var summaries: [Int: ThreadSummary] = [:]
    private(set) var reactions: [Int: [MessageReaction]] = [:]
    private(set) var typing: [Int] = []
    var unread: Int { state.chat.unreadCount }
    private(set) var rows: [ChatListRow] = []

    // MARK: paging
    var loadingOlder = false
    var reachedStart = false
    var loadingNewer = false
    /// A jump window found nothing newer and could not join the timeline: it stops asking (the jump-to-latest button
    /// still goes there).
    var newerExhausted = false
    /// Set when a load failed: automatic loading stops (no retry loop while offline) and the header offers a button.
    var loadFailed = false

    // MARK: scrolling
    /// Scrolled up far enough to show the jump-to-latest button.
    var away = false { didSet { if away != oldValue { awayChanged() } } }
    /// Messages that arrived since the user scrolled away from the bottom.
    private(set) var unseen = 0
    var scrollRequest: ChatScrollRequest?
    /// The message (server id) briefly highlighted after a jump to it.
    var highlighted: Int?

    // MARK: inputs the view keeps current
    var reactionsOn = false { didSet { if reactionsOn != oldValue { reactionsSettingChanged() } } }
    var markerGap: TimeInterval? { didSet { if markerGap != oldValue { rebuildRows() } } }
    /// Reports a failure to the user (the view shows a toast).
    var report: (String) -> Void = { _ in }
    /// Tells the user something went fine (copied).
    var notify: (String) -> Void = { _ in }
    /// Translations shown under messages.
    let translation: MessageTranslationController

    var typingRoster = TypingRoster()

    // MARK: behind another chat
    /// The messages that came in while the chat was kept behind another one (`heldBack`), for `backOnScreen()`.
    @ObservationIgnored private var held: [ChatMessage]?
    /// Replies or reactions, or what the rows are built from, changed meanwhile.
    @ObservationIgnored private var heldDetails = false
    @ObservationIgnored private var heldRows = false
    /// The window whose messages are the ones shown.
    @ObservationIgnored private var shownWindow: ChatMessageWindow?
    /// Whether what comes in waits: the chat has its messages and is kept behind another one, where nobody sees it. A
    /// message taken in there rebuilt its rows, measured them and drew them all the same - some 25 ms of the main thread
    /// a message on an optimized build, for each chat kept - so a busy group behind the open chat made the open one
    /// stutter. What waited is taken in at once when the chat is shown again.
    private var heldBack: Bool { loaded && !state.isOnScreen }
    @ObservationIgnored private var replies: [ChatMessage] = []
    let windowEvents: AsyncStream<ChatMessageWindow>.Continuation
    private let windowStream: AsyncStream<ChatMessageWindow>
    var messagesTask: Task<Void, Never>?
    var markingRead = false
    /// The message that was first before older rows were added above it (the list keeps it in place).
    var prependedAnchor: String?
    /// A page was asked for and its window is set; the busy flags drop when that window's messages arrive.
    var awaitingGrowth = false
    /// How many times older rows were added above the first one (the list restores the reader's place each time).
    var prependCount = 0

    init(state: ChatThreadState, services: ChatServices) {
        self.state = state; self.services = services
        translation = MessageTranslationController(services: services)
        (windowStream, windowEvents) = AsyncStream<ChatMessageWindow>.makeStream(bufferingPolicy: .bufferingNewest(1))
        windowEvents.yield(window)
    }

    /// The chat is on screen again: what came in behind the other chat is shown.
    func backOnScreen() {
        if let list = held { held = nil; apply(list, window: window, arrivedNow: false) }
        if heldDetails { heldDetails = false; rebuildReplyDetails() }
        if heldRows { heldRows = false; rebuildRows() }
    }

    /// Runs the timeline's watchers until the task is cancelled (the view's `.task`).
    func run() async {
        // Here and not in `init`: the view builds a model every time it is made again and keeps only its first one. The
        // ones thrown away took these over and were gone at once, so the chat was told nothing - and what came in
        // behind another chat stayed out of the list when the chat was shown again.
        state.onBackOnScreen = { [weak self] in self?.backOnScreen() }
        state.onSentToChat = { [weak self] in self?.showLatestForSend() }
        defer { messagesTask?.cancel() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeWindows() }
            group.addTask { await self.observeReplies() }
            group.addTask { await self.observeTyping() }
            group.addTask { await self.pruneTyping() }
        }
    }

    // MARK: watchers

    /// Watches the messages of the current window, switching streams whenever the window changes.
    private func observeWindows() async {
        for await w in windowStream {
            messagesTask?.cancel()
            let chat = services.chat, account = accountId, gid = chatGid, withReactions = reactionsOn
            let stream: AsyncStream<[ChatMessage]> = switch w {
            case .live(let limit): chat.watchMessages(accountId: account, chatGid: gid, limit: limit, reactions: withReactions)
            case .around(let from, let to): chat.watchMessagesInRange(accountId: account, chatGid: gid, fromIndex: from, toIndex: to, reactions: withReactions)
            }
            messagesTask = Task { [weak self] in
                for await list in stream { guard let self, !Task.isCancelled else { return }; self.apply(list, window: w) }
            }
        }
    }

    private func observeReplies() async {
        for await list in services.chat.watchReplies(accountId: accountId, chatGid: chatGid) {
            replies = list
            if heldBack { heldDetails = true } else { rebuildReplyDetails() }
        }
    }

    /// Replies and emoji reactions come from the same stored rows.
    private func rebuildReplyDetails() {
        let nextSummaries = BuildReplyThread().summariesByRoot(replies, reactions: reactionsOn)
        let nextReactions = reactionsOn ? BuildReactions()(replies) : [:]
        if nextSummaries != summaries { summaries = nextSummaries }
        if nextReactions != reactions { reactions = nextReactions }
    }

    /// Reactions and reply summaries follow the user's setting; the message streams re-read with the new filter.
    private func reactionsSettingChanged() {
        rebuildReplyDetails()
        windowEvents.yield(window)
    }

    // MARK: messages

    private func apply(_ list: [ChatMessage], window w: ChatMessageWindow, arrivedNow: Bool = true) {
        guard w == window else { return }
        // Behind another chat only a change of window is taken in (the list going back to its newest messages, so the
        // chat comes back there): more of the same window waits.
        if heldBack, w == shownWindow { held = list; return }
        held = nil
        shownWindow = w
        let before = messages
        // Opening a chat reads its window more than once (the reactions setting restarts the stream): the same messages
        // again change nothing on screen, and re-setting them re-ran the list for nothing.
        if !loaded || list != before {
            messages = list
            if !loaded { loaded = true }
            buildRows()
        }
        notePrepended(before, list)
        if awaitingGrowth { awaitingGrowth = false; loadingOlder = false; loadingNewer = false }
        // Back from a jump window to the latest messages.
        markReadIfSeen()
        if window.isAround || !arrivedNow { return }
        guard let newest = before.last?.gid, let last = list.last, last.gid != newest,
              let at = list.firstIndex(where: { $0.gid == newest }) else { return }
        let arrived = list[(at + 1)...]
        let selfId = state.selfUserId
        // Own message: from far up, an animated trip down; at the bottom already, the list's bottom anchor keeps it in view,
        // and an extra animated scroll only made the newest bubble jump at the bottom edge.
        if arrived.contains(where: { $0.isMine || $0.senderId == selfId }), away { scroll(to: .bottom) }
        else if away { unseen += arrived.count }
    }

    /// The rows again, from the messages, the time-marker gap and who is typing - once the chat is seen, when it is not now.
    func rebuildRows() {
        if heldBack { heldRows = true } else { buildRows() }
    }

    private func buildRows() {
        let typingRow = !window.isAround && !away && !typing.isEmpty, messages = messages, gap = markerGap
        let next = PerformanceLog.measureSync("chat: build \(messages.count) rows") { ChatListRows.rows(messages, markerGap: gap, typing: typingRow) }
        // The list redraws when `rows` is set, also to the same rows (scrolling away and back, the style re-applied).
        if next != rows { rows = next }
    }

    private func awayChanged() {
        if !away { unseen = 0; markReadIfSeen() }
        rebuildRows()
    }

    func scroll(to target: ChatScrollRequest.Target, animated: Bool = true) {
        scrollRequest = ChatScrollRequest(target: target, animated: animated)
    }

    /// Marks the chat read while its newest messages are on screen — not while the user reads older ones, nor in a window
    /// jumped far back, nor while the chat is kept open behind another one.
    func markReadIfSeen() {
        guard state.isOnScreen, !away, !window.isAround, unread > 0, !markingRead else { return }
        markingRead = true
        let chat = services.chat, account = accountId, gid = chatGid
        Task { [weak self] in
            _ = await MarkChatRead(chat)(accountId: account, chatGid: gid)
            self?.markingRead = false
        }
    }

    func setTyping(_ ids: [Int]) { typing = ids; rebuildRows() }

    /// The shown message with this server id.
    func shownMessage(serverId: Int) -> ChatMessage? { messages.first { $0.serverId == serverId } }
}
