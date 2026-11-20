/// Ported from: lib/features/chat/presentation/providers/chat_person_providers.dart
import CoreDomain
import Foundation
import Observation

/// What a person's profile popup shows beyond chat's own user record: their tracker profile, the groups the signed-in user
/// shares with them, and their open synced work. Each part loads on its own; one that cannot is left out or says so.
@MainActor @Observable
final class ChatProfileModel {
    enum Load<T> {
        case loading, loaded(T), failed
        var value: T? { if case .loaded(let v) = self { v } else { nil } }
        var isLoading: Bool { if case .loading = self { true } else { false } }
        var failed: Bool { if case .failed = self { true } else { false } }
    }

    /// nil: there is no tracker to ask.
    private(set) var profile: Load<PersonProfile>?
    /// nil: not asked (your own profile).
    private(set) var groups: Load<[ChatConversation]>?
    private(set) var tickets = PersonTickets()

    /// Reads the tracker profile and the shared groups (unless `isSelf`).
    func load(services: ChatServices?, accountId: String, userId: Int, isSelf: Bool) async {
        let people = services?.people, repository = services?.chat
        profile = people == nil ? nil : .loading
        groups = isSelf || repository == nil ? nil : .loading
        let shareWith = isSelf ? nil : repository
        async let person = Self.lookup(people, accountId, userId)
        async let shared = Self.sharedGroups(shareWith, accountId, userId)
        if let p = await person { profile = (try? p.get()).map { .loaded($0) } ?? .failed }
        if let s = await shared { groups = (try? s.get()).map { .loaded($0) } ?? .failed }
    }

    private nonisolated static func lookup(_ people: PersonDirectory?, _ accountId: String, _ userId: Int) async -> Outcome<PersonProfile>? {
        await people?.lookup(accountId: accountId, userId: userId)
    }

    private nonisolated static func sharedGroups(_ repository: ChatRepository?, _ accountId: String, _ userId: Int) async -> Outcome<[ChatConversation]>? {
        guard let repository else { return nil }
        return await FindSharedGroups(repository)(accountId: accountId, userId: userId)
    }

    /// Follows the synced tickets for `handle`'s open work while the popup is up.
    func watchTickets(services: ChatServices?, accountId: String, handle: String?) async {
        guard let watch = services?.watchTickets, let handle, !handle.isEmpty else { return }
        for await all in watch() {
            // Off the main thread: the whole ticket table is gone through on every write.
            let next = await Task.detached(priority: .utility) { ListPersonTickets()(all, accountId: accountId, handle: handle) }.value
            if next != tickets { tickets = next }
        }
    }
}
