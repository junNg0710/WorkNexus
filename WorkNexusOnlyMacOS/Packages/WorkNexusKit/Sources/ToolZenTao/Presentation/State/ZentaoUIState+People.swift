/// Not in the Flutter app.
import Foundation

extension ZentaoUIState {
    /// The people the leader keeps at the front of the people strip on this account, in order.
    var pinnedPeople: [String] {
        _ = pinnedPeopleRevision
        guard let accountId = placeAccountId else { return [] }
        return deps.pinnedPeople.pinned(accountId: accountId)
    }

    /// The people tickets were handed to lately on this account, most recent first.
    var recentAssignees: [String] {
        _ = pinnedPeopleRevision
        guard let accountId = placeAccountId else { return [] }
        return deps.recentAssignees.recent(accountId: accountId)
    }

    /// Who the quick Assign menu offers: the pinned people, then the recent ones.
    var quickAssignees: [String] { ListQuickAssignees()(pinned: pinnedPeople, recent: recentAssignees) }

    /// `login` was just handed tickets on `accountId`.
    func rememberAssignee(_ login: String, accountId: String) {
        deps.recentAssignees.setRecent(RememberRecentAssignee()(deps.recentAssignees.recent(accountId: accountId), login), accountId: accountId)
        pinnedPeopleRevision += 1
    }

    func togglePinned(_ login: String) { setPinned(TogglePinnedPerson()(pinnedPeople, login)) }

    /// `login` dropped onto `target` in the strip.
    func movePerson(_ login: String, before target: String) { setPinned(MovePinnedPerson()(pinnedPeople, move: login, before: target)) }

    private func setPinned(_ logins: [String]) {
        guard let accountId = placeAccountId else { return }
        deps.pinnedPeople.setPinned(logins, accountId: accountId)
        pinnedPeopleRevision += 1
    }
}
