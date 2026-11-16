import CoreDomain
import Foundation
import Observation

/// The pinned messages of one chat: each followed by its server id; ones not stored here are fetched from the server once.
/// Ported from: lib/features/chat/presentation/widgets/pinned_messages_panel.dart
@MainActor @Observable
final class PinnedMessagesModel {
    private(set) var messages: [Int: ChatMessage] = [:]
    /// Ids the server has answered for (a message it did not return is gone, not waited for).
    private(set) var answered: Set<Int> = []
    private(set) var failed = false
    @ObservationIgnored private var watched: Set<Int> = []
    @ObservationIgnored private var requested: Set<Int> = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let repository: ChatRepository
    @ObservationIgnored private let accountId: String
    @ObservationIgnored private let chatGid: String

    init(accountId: String, chatGid: String, repository: ChatRepository) {
        self.accountId = accountId; self.chatGid = chatGid; self.repository = repository
    }

    /// Follows `ids` and fetches the ones that turn out missing.
    func track(_ ids: [Int]) {
        for id in ids where watched.insert(id).inserted {
            tasks.append(Task { [weak self] in
                guard let self else { return }
                for await m in repository.watchMessage(accountId: accountId, chatGid: chatGid, serverId: id) {
                    if let m { messages[id] = m } else { messages[id] = nil; fetchMissing([id]) }
                }
            })
        }
    }

    func fetchMissing(_ ids: [Int]) {
        let missing = ids.filter { requested.insert($0).inserted }
        guard !missing.isEmpty, !failed else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.fetchMessages(accountId: accountId, chatGid: chatGid, serverIds: missing)
            answered.formUnion(missing)
            if case .failure = result { failed = true }
        }
    }

    func retry(_ ids: [Int]) {
        failed = false
        requested.subtract(ids); answered.subtract(ids)
        fetchMissing(ids.filter { messages[$0] == nil })
    }

    func stop() { tasks.forEach { $0.cancel() }; tasks = [] }
}
