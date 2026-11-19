/// Ported from: lib/features/chat/presentation/providers/chat_ai_providers.dart (`ChatReplySuggestionsController`,
/// `ChatDraftRewriteController`, `_latest`, `_model`)
import CoreDomain
import Foundation
import Observation

/// Where an AI run of the composer stands.
enum ChatAiPhase<Value: Equatable>: Equatable {
    case idle, loading, ready(Value), failed(String)
}

/// What the AI runs read: the chat's services and settings, and its latest stored messages.
@MainActor
struct ChatAiContext {
    let services: ChatServices
    let settings: ChatSettings
    let state: ChatThreadState

    var ai: ChatAiTextGenerator? { services.ai }
    var people: ChatAiPeople { ChatAiPeople(users: state.users, selfUserId: state.selfUserId) }

    /// The people with their roles in brackets, for reply ideas (`Lan (QA tester)`).
    var peopleWithRoles: ChatAiPeople {
        let names = state.roleNames
        return ChatAiPeople(users: state.users, selfUserId: state.selfUserId) { user in
            guard let code = user.role?.trimmingCharacters(in: .whitespaces), !code.isEmpty else { return nil }
            return ChatReplyRole.fromZenTao(code)?.englishName ?? names[code] ?? code
        }
    }

    /// How the user writes in the team, for reply ideas: the role picked in the ✨ menu, else the ZenTao one.
    var selfRole: String? {
        let code = state.selfUserId.flatMap { state.users[$0]?.role }
        return ResolveReplyRole()(settings.replyRole, zenTaoRole: code, roleName: code.flatMap { state.roleNames[$0] })
    }
    /// The model pinned in Settings for the AI backend; nil leaves it its own.
    var model: String? { settings.translationModel.isEmpty ? nil : settings.translationModel }

    /// The AI backend is set up (asks the host, which explains how to set one up when it is not).
    func ready() async -> Bool { await (services.ensureAiReady ?? services.ensureTranslatorReady)?() ?? true }

    /// The newest `limit` stored messages of the chat (the transcript orders them itself).
    func latest(_ limit: Int) async -> [ChatMessage] {
        var it = services.chat.watchMessages(accountId: state.accountId, chatGid: state.chatGid, limit: limit, reactions: false)
            .makeAsyncIterator()
        return await it.next() ?? []
    }
}

/// The composer's AI help: reply ideas (shown in the tray above the tools, picked into the input, never sent) and draft
/// rewrites. Lives as long as the composer; leaving it stops what it asked for.
@MainActor @Observable
final class ChatComposerAi {
    /// How many of the latest messages reply ideas and rewrites look at.
    static let contextMessages = 20

    private(set) var replies: ChatAiPhase<[String]> = .idle
    private(set) var rewriting = false
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var busyKeys = Set<String>()
    @ObservationIgnored private var ai: ChatAiTextGenerator?
    private let state: ChatThreadState

    init(state: ChatThreadState) { self.state = state }

    private var repliesKey: String { "chat-replies:\(state.accountId):\(state.chatGid)" }
    private var rewriteKey: String { "chat-rewrite:\(state.accountId):\(state.chatGid)" }

    func suggest(_ context: ChatAiContext) async {
        guard let ai = context.ai, await context.ready() else { return }
        self.ai = ai
        run += 1
        let mine = run
        replies = .loading
        busyKeys.insert(repliesKey)
        let messages = await context.latest(Self.contextMessages)
        let people = context.peopleWithRoles
        let result = await SuggestChatReplies(ai)(messages, key: repliesKey, selfName: people.selfName, nameOf: people.name(of:),
                                                  selfRole: context.selfRole, model: context.model)
        guard mine == run else { return }
        busyKeys.remove(repliesKey)
        switch result {
        case .success(let list): replies = .ready(list)
        case .failure(let f): replies = .failed(f.message)
        }
    }

    /// Closes the replies, stopping a run still in progress.
    func clearReplies() {
        run += 1
        replies = .idle
        cancel(repliesKey)
    }

    /// `draft` rewritten in `tone`, in the light of the latest messages; nil when the backend is not set up.
    func rewrite(_ draft: String, tone: ChatDraftTone, context: ChatAiContext) async -> Outcome<String>? {
        guard let ai = context.ai, await context.ready() else { return nil }
        self.ai = ai
        rewriting = true
        busyKeys.insert(rewriteKey)
        defer { rewriting = false; busyKeys.remove(rewriteKey) }
        let recent = await context.latest(Self.contextMessages)
        let people = context.people
        return await RewriteChatDraft(ai)(draft, tone: tone, key: rewriteKey, context: recent, selfName: people.selfName,
                                          nameOf: people.name(of:), model: context.model)
    }

    /// The composer goes away: what it asked for is stopped.
    func stop() {
        for key in busyKeys { cancel(key) }
    }

    /// Stops the run named `key` when one is in progress.
    private func cancel(_ key: String) {
        guard busyKeys.remove(key) != nil, let ai else { return }
        Task { await ai.cancel(key) }
    }
}
