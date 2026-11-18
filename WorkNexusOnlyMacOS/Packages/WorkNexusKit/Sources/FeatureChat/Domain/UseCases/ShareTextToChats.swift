/// Not in the Flutter app: sharing a link (a ticket's) into chats from elsewhere in the app.
import CoreDomain
import Foundation

/// Sends `text` to each of `chatGids` in turn; the first failure stops it and is returned.
public struct ShareTextToChats: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, chatGids: [String], text: String) async -> Outcome<Void> {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return .failure(.validation("Nothing to share")) }
        guard !chatGids.isEmpty else { return .failure(.validation("No chat picked")) }
        for gid in chatGids {
            if case .failure(let f) = await repository.sendText(accountId: accountId, chatGid: gid, text: body, replyToId: nil, markdown: false) {
                return .failure(f)
            }
        }
        return .success(())
    }
}
