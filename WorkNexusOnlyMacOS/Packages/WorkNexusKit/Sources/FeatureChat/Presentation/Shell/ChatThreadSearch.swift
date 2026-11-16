import CoreDomain
import Foundation
import Observation

/// The in-chat message search: the matches of the query (newest first), a cursor stepping through them and paging for more.
/// Ported from: lib/features/chat/presentation/providers/chat_search_providers.dart + widgets/chat_thread_search_bar.dart
@MainActor @Observable
final class ChatThreadSearch {
    /// How many results one page brings; stepping past the last one asks for another page.
    static let pageSize = 100

    var isOpen = false
    private(set) var query = ""
    private(set) var matches: [ChatMessage] = []
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var failed = false
    /// 0-based; -1 until the first step, so that step lands on the first match rather than the second.
    var activeIndex = -1

    @ObservationIgnored private let accountId: String
    @ObservationIgnored private let chatGid: String
    @ObservationIgnored private let repository: ChatRepository
    @ObservationIgnored private let period: () -> ChatSearchPeriod
    @ObservationIgnored private let debounce: Duration
    /// Told the query changed (the message list highlights it) and which message to jump to.
    @ObservationIgnored var onQuery: (String) -> Void = { _ in }
    @ObservationIgnored var onJump: (Int) -> Void = { _ in }
    @ObservationIgnored private var limit = pageSize
    @ObservationIgnored private var task: Task<Void, Never>?

    init(accountId: String, chatGid: String, repository: ChatRepository, period: @escaping () -> ChatSearchPeriod,
         debounce: Duration = .milliseconds(200)) {
        self.accountId = accountId; self.chatGid = chatGid; self.repository = repository
        self.period = period; self.debounce = debounce
    }

    /// Where stepping `delta` lands: wraps around, and asks for a page first when it runs past the oldest loaded match
    /// while more are stored. Nil when there are no matches.
    static func nextIndex(current: Int, count: Int, hasMore: Bool, delta: Int) -> (index: Int, needsMore: Bool)? {
        guard count > 0 else { return nil }
        if current < 0 || current >= count { return (delta > 0 ? 0 : count - 1, false) }
        if current + delta >= count && hasMore { return (current + delta, true) }
        return ((current + delta + count) % count, false)
    }

    func setQuery(_ text: String) {
        query = text; activeIndex = -1; limit = Self.pageSize
        onQuery(text)
        reload(after: debounce)
    }

    /// Searches again (another period, or more history arrived).
    func reload(after delay: Duration = .zero) {
        task?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            matches = []; hasMore = false; isLoading = false; failed = false
            return
        }
        isLoading = true
        task = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    private func run() async {
        let q = query, n = limit
        let result = await repository.searchMessages(accountId: accountId, chatGid: chatGid, query: q,
                                                     since: period().since(Date()), limit: n + 1)
        guard !Task.isCancelled, q == query else { return }
        switch result {
        case .success(let found): matches = Array(found.prefix(n)); hasMore = found.count > n; failed = false
        case .failure: failed = true
        }
        isLoading = false
    }

    /// Steps `delta` matches older (positive) or newer and jumps to the one reached.
    func step(_ delta: Int) async {
        guard let next = Self.nextIndex(current: activeIndex, count: matches.count, hasMore: hasMore, delta: delta) else { return }
        if next.needsMore {
            limit += Self.pageSize
            task?.cancel()
            await run()
            guard next.index < matches.count else { return }
        }
        activeIndex = next.index
        if let serverId = matches[next.index].serverId { onJump(serverId) }
    }

    func close() {
        task?.cancel(); isOpen = false; query = ""; matches = []; hasMore = false; isLoading = false; failed = false
        activeIndex = -1; onQuery("")
    }

    func cancel() { task?.cancel() }
}
