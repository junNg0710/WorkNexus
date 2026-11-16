/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SwiftUI

/// Creates or edits a team group: a name and the people of the account to follow.
struct ZentaoTeamGroupDialog: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let account: Account; let bugs: Bool
    let editing: ZenTaoTeamGroup?; let onClose: () -> Void
    @State private var name: String
    @State private var picked: [String: ZenTaoTeamMember]
    @State private var users: ZentaoLoad<[ProviderUser]> = .loading
    @State private var filter = ""
    @State private var busy = false

    init(deps: ZentaoDependencies, state: ZentaoUIState, account: Account, bugs: Bool, editing: ZenTaoTeamGroup?, onClose: @escaping () -> Void) {
        self.deps = deps; self.state = state; self.account = account; self.bugs = bugs; self.editing = editing; self.onClose = onClose
        _name = State(initialValue: editing?.name ?? "")
        _picked = State(initialValue: Dictionary((editing?.members ?? []).map { ($0.login, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    private var result: Result<ZenTaoTeamGroup, BuildTeamGroup.Problem> {
        BuildTeamGroup()(id: editing?.id, accountId: account.id, name: name, members: Array(picked.values),
                         createdAt: editing?.createdAt ?? Date())
    }

    private func submit() {
        guard case .success(let group) = result else { return }
        busy = true
        Task {
            _ = await state.saveTeamGroup(group)
            // A group made now is shown right away.
            if editing == nil { state.openTeam(group, bugs: bugs) }
            onClose()
        }
    }

    private func visible(_ all: [ProviderUser]) -> [ProviderUser] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        // A member the user list no longer has (left, renamed) stays on the list so it can be taken off.
        let known = Set(all.map(\.account))
        let missing = picked.values.filter { !known.contains($0.login) }.map { ProviderUser(account: $0.login, displayName: $0.name) }
        return (missing + all).filter { q.isEmpty || "\($0.displayName) \($0.account)".lowercased().contains(q) }
    }

    var body: some View {
        let ok = (try? result.get()) != nil
        ZentaoActionFrame(title: editing == nil ? appString("leaderNewGroup", "New team group…") : appString("leaderEditGroup", "Edit this group…"),
                          icon: "person.3", submitLabel: appString("save", "Save"), busy: busy, canSubmit: ok, onSubmit: submit, onClose: onClose) {
            ZentaoFieldLabel(appString("leaderGroupName", "Group name"))
            ZentaoTextInput(text: $name)
            ZentaoFieldGap()
            ZentaoFieldLabel(appFormat("leaderGroupPeople", "People (%1$@ picked)", "\(picked.count)"))
            AppSearchField(text: $filter, hint: appString("searchUsers", "Search users…"))
            Color.clear.frame(height: theme.spacing.s8)
            switch users {
            case .loading: AppInlineSpinner()
            case .failed: AppInlineNote(appString("taskDetailUsersLoadFailed", "Couldn't load users"), isError: true)
            case .loaded(let all): list(visible(all))
            }
        }
        .task { await loadUsers() }
    }

    private func list(_ people: [ProviderUser]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(people) { u in
                    let on = picked[u.account] != nil
                    HoverSurface(onTap: {
                        if on { picked[u.account] = nil } else { picked[u.account] = ZenTaoTeamMember(login: u.account, name: u.displayName) }
                    }, cornerRadius: theme.radii.sm) {
                        HStack(spacing: theme.spacing.s8) {
                            Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? theme.colors.accent : theme.colors.tx3)
                            Text(u.displayName).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
                            Text(u.account).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
                    }
                }
            }
        }
        .frame(height: 260)
    }

    private func loadUsers() async {
        guard let acc = await deps.account(id: account.id), let adapter = await deps.services.sync.adapter(for: acc) else {
            users = .failed(.auth("No stored credentials for this account")); return
        }
        switch await adapter.listUsers() {
        case .success(let l): users = .loaded(l)
        case .failure(let f): users = .failed(f)
        }
    }
}
