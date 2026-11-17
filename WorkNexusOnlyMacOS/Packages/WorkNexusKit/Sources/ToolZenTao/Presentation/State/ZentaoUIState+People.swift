/// Not in the Flutter app.
import Foundation

extension ZentaoUIState {
    /// The people the leader keeps at the front of the people strip on this account, in order.
    var pinnedPeople: [String] {
        _ = pinnedPeopleRevision
        guard let accountId = place.accountId else { return [] }
        return deps.pinnedPeople.pinned(accountId: accountId)
    }

    func togglePinned(_ login: String) { setPinned(TogglePinnedPerson()(pinnedPeople, login)) }

    /// `login` dropped onto `target` in the strip.
    func movePerson(_ login: String, before target: String) { setPinned(MovePinnedPerson()(pinnedPeople, move: login, before: target)) }

    private func setPinned(_ logins: [String]) {
        guard let accountId = place.accountId else { return }
        deps.pinnedPeople.setPinned(logins, accountId: accountId)
        pinnedPeopleRevision += 1
    }
}
