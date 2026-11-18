/// Ported from: lib/features/chat/presentation/providers/chat_ai_providers.dart (`chatUnreadOnOpenProvider`,
/// `chatCatchUpDismissedProvider`, `chatOffersCatchUpProvider`, `chatSummaryLanguageProvider`, `chatSummaryScopeProvider`,
/// `ChatSummaryController`) + widgets/chat_ai_actions.dart (`summarizeChat`)
import CoreDomain
import CoreUI
import Foundation
import Observation

/// Which messages a summary covers: the ones that were unread, or the latest `count`.
struct ChatSummaryScope: Equatable {
    var unread: Bool
    var count: Int
    /// The latest-message counts offered besides the unread ones.
    static let latestCounts = [50, 100, 200]
    /// The most messages a summary reads, however many are unread.
    static let maxMessages = 300
}

/// The language summaries are written in, picked in the assistant panel; nil writes them in the app's language. Kept while
/// the app runs, for every chat, so a reader who wants summaries in another language picks it once.
@MainActor @Observable
final class ChatAiPreferences {
    static let shared = ChatAiPreferences()
    var summaryLanguage: String?
}

/// The AI summary of one chat: idle until one is asked for. Kept while the app runs, on purpose: a summary costs a model call,
/// so closing and reopening the panel (or the chat) shows it again instead of paying for a new one; "Summarize again" makes a
/// fresh one.
@MainActor @Observable
final class ChatSummaryModel {
    private static var all: [String: ChatSummaryModel] = [:]
    static func of(accountId: String, chatGid: String) -> ChatSummaryModel {
        let key = "\(accountId):\(chatGid)"
        if let known = all[key] { return known }
        let made = ChatSummaryModel(key: "chat-summary:\(key)")
        all[key] = made
        return made
    }

    private(set) var phase: ChatAiPhase<ChatSummary> = .idle
    var isLoading: Bool { phase == .loading }
    var summary: ChatSummary? { if case .ready(let s) = phase { s } else { nil } }
    /// Bumped by each run and by `cancel`, so a run that was cancelled or overtaken leaves the state alone when it finishes.
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var ai: ChatAiTextGenerator?
    private let key: String
    private init(key: String) { self.key = key }

    /// Summarizes the latest `count` messages in `language`.
    func summarize(count: Int, language: ChatAiLanguage, context: ChatAiContext) async {
        guard let ai = context.ai else { return }
        self.ai = ai
        run += 1
        let mine = run
        phase = .loading
        let messages = await context.latest(min(max(count, 1), ChatSummaryScope.maxMessages))
        let people = context.people
        let result = await SummarizeChat(ai)(messages, key: key, languageName: language.englishName, selfName: people.selfName,
                                             nameOf: people.name(of:), model: context.model)
        guard mine == run else { return }
        switch result {
        case .success(let s): phase = .ready(s)
        case .failure(let f): phase = .failed(f.message)
        }
    }

    /// Stops a summary in progress and forgets it.
    func cancel() {
        run += 1
        phase = .idle
        if let ai { Task { [key] in await ai.cancel(key) } }
    }
}

/// The assistant of one visit to a chat: how many messages were unread when it opened (what the catch-up banner offers to
/// summarize), whether that banner was dismissed, and the scope picked in the panel. The summary itself outlives the visit
/// (`ChatSummaryModel`).
@MainActor @Observable
final class ChatAssistantModel {
    let summary: ChatSummaryModel
    private(set) var unreadOnOpen = 0
    var catchUpDismissed = false
    /// The unread messages when there are enough of them to be worth it, the latest 50 otherwise.
    var scope = ChatSummaryScope(unread: false, count: 50)

    init(accountId: String, chatGid: String) { summary = .of(accountId: accountId, chatGid: chatGid) }

    /// The chat opened with `unread` messages, before opening marks them read.
    func opened(unread: Int) {
        unreadOnOpen = unread
        if ShouldOfferChatSummary()(unread: unread) { scope = ChatSummaryScope(unread: true, count: unread) }
    }

    /// Whether the banner over the messages offers to summarize what came in meanwhile.
    var offersCatchUp: Bool { ShouldOfferChatSummary()(unread: unreadOnOpen) && !catchUpDismissed }

    /// The language summaries are written in: the one picked in the panel, else the app's.
    func language(_ offered: [ChatAiLanguage]) -> ChatAiLanguage {
        ResolveChatSummaryLanguage()(picked: ChatAiPreferences.shared.summaryLanguage, appLanguage: AppLanguage.current, offered: offered)
    }

    /// Opens the assistant beside the chat and summarizes `scope` there, once an AI backend is set up (otherwise the host
    /// explains how to set one up). `onStart` runs once the summary starts.
    func summarize(_ scope: ChatSummaryScope, context: ChatAiContext, onStart: (() -> Void)? = nil) async {
        context.state.sidePanel = .assistant
        self.scope = scope
        let language = language(context.services.aiLanguages)
        guard await context.ready() else { return }
        onStart?()
        await summary.summarize(count: scope.count, language: language, context: context)
    }
}
