/// Not in the Flutter app: sharing a link (a ticket's) into chats from elsewhere in the app.
import CoreDomain
import Foundation

/// Sends `text` to each of `chatGids` in turn, after `note` when there is one (a line or two of the sender's own, its
/// mentions already written as `[@Name](@#id)`); the first failure stops it and is returned. Each goes out as a typed
/// message does (`SendTextMessage`: emoji encoded for the server).
public struct ShareTextToChats: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, chatGids: [String], text: String, note: String = "") async -> Outcome<Void> {
        let body = Self.message(text: text, note: note)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.validation("Nothing to share")) }
        guard !chatGids.isEmpty else { return .failure(.validation("No chat picked")) }
        let send = SendTextMessage(repository)
        for gid in chatGids {
            if case .failure(let f) = await send(accountId: accountId, chatGid: gid, text: body, replyToId: nil, markdown: false) {
                return .failure(f)
            }
        }
        return .success(())
    }

    /// The note, a blank line, then what is shared; just what is shared without a note.
    static func message(text: String, note: String) -> String {
        let shared = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let said = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return said.isEmpty ? shared : "\(said)\n\n\(shared)"
    }
}
