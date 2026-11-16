import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/user_picker_editor.dart
/// Pure selection rules of the picker (testable without a view).
enum GitlabUserSelection {
    /// The accounts of `users` the item already has: `current` holds logins or display names.
    static func initial(users: [ProviderUser], current: [String]) -> Set<String> {
        let names = Set(current)
        return Set(users.filter { names.contains($0.account) || names.contains($0.displayName) }.map(\.account))
    }

    /// The users matching the search box (display name or account).
    static func visible(_ users: [ProviderUser], query: String) -> [ProviderUser] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? users : users.filter { $0.displayName.lowercased().contains(q) || $0.account.lowercased().contains(q) }
    }

    /// Picking `account`: toggles in a multi picker, replaces in a single one.
    static func toggled(_ selected: Set<String>, _ account: String, multiple: Bool) -> Set<String> {
        guard multiple else { return [account] }
        var next = selected
        if next.contains(account) { next.remove(account) } else { next.insert(account) }
        return next
    }
}

/// A searchable list of provider users: single pick (assignee) or multi (reviewers), with a Save footer.
struct GitlabUserPickerEditor: View {
    @Environment(\.appTheme) private var theme
    let currentUsers: [String]; let multiple: Bool
    let loadUsers: () async -> Outcome<[ProviderUser]>
    let onSave: ([String]) async -> Outcome<Void>
    let onClose: () -> Void
    let avatarLoader: AvatarLoader
    /// 340pt in a popover; nil fills the width it is given (a dialog).
    var width: CGFloat? = 340
    @State private var loaded: Outcome<[ProviderUser]>?
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            GitlabEditorSearchField(text: $query, hint: appString("searchUsers", "Search users…"))
            switch loaded {
            case nil: AppStateView(.loading)
            case .failure(let f)?: AppStateView(.error(f.message))
            case .success(let users)?:
                GitlabUserOptionsList(users: users, query: query, multiple: multiple, selected: selected, avatarLoader: avatarLoader) {
                    error = nil
                    selected = $0
                }
            }
            GitlabEditorFooter(busy: busy, error: error, onSave: !multiple && selected.isEmpty ? nil : save)
        }
        .frame(minWidth: width, maxWidth: width ?? .infinity).frame(height: 380)
        .background(theme.colors.card)
        .task {
            let result = await loadUsers()
            if case .success(let users) = result { selected = GitlabUserSelection.initial(users: users, current: currentUsers) }
            loaded = result
        }
    }

    private func save() {
        busy = true; error = nil
        let accounts = selected.sorted()
        Task {
            let result = await onSave(accounts)
            busy = false
            switch result {
            case .success: onClose()
            case .failure(let f): error = f.message
            }
        }
    }
}

/// The scrolling options of the picker; `onChange` gets the new selection after a pick / clear.
private struct GitlabUserOptionsList: View {
    let users: [ProviderUser]; let query: String; let multiple: Bool; let selected: Set<String>
    let avatarLoader: AvatarLoader; let onChange: (Set<String>) -> Void

    var body: some View {
        let visible = GitlabUserSelection.visible(users, query: query)
        ScrollView {
            LazyVStack(spacing: 0) {
                if multiple {
                    GitlabEditorOptionTile(title: appString("unassigned", "Unassigned"), selected: selected.isEmpty) { onChange([]) }
                }
                if visible.isEmpty {
                    GitlabEditorMessage(message: users.isEmpty ? appString("taskDetailNoAssignableUsers", "No assignable users")
                                                               : appString("noMatchingUsers", "No matching users"))
                }
                ForEach(visible) { user in
                    GitlabEditorOptionTile(
                        title: user.displayName, subtitle: "@\(user.account)", selected: selected.contains(user.account),
                        leading: AnyView(ProviderAvatarImage(name: user.displayName, avatarUrl: user.avatarUrl, imageLoader: avatarLoader))
                    ) { onChange(GitlabUserSelection.toggled(selected, user.account, multiple: multiple)) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
