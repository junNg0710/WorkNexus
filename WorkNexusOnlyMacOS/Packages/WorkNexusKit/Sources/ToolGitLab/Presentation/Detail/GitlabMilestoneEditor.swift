import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/milestone_editor.dart
/// A searchable single pick of the project's milestones (or none) with a Save footer.
struct GitlabMilestoneEditor: View {
    @Environment(\.appTheme) private var theme
    let currentMilestoneId: Int?
    let loadOptions: () async -> Outcome<[ProviderMilestoneOption]>
    let onSave: (Int?) async -> Outcome<Void>
    let onClose: () -> Void
    @State private var loaded: Outcome<[ProviderMilestoneOption]>?
    @State private var selected: Int?
    @State private var query = ""
    @State private var error: String?
    @State private var busy = false

    /// The milestones matching the search box.
    static func visible(_ options: [ProviderMilestoneOption], query: String) -> [ProviderMilestoneOption] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? options : options.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            GitlabEditorSearchField(text: $query, hint: appString("searchMilestones", "Search milestones…"))
            switch loaded {
            case nil: AppStateView(.loading)
            case .failure(let f)?: AppStateView(.error(f.message))
            case .success(let options)?:
                let visible = Self.visible(options, query: query)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        GitlabEditorOptionTile(title: appString("none", "None"), selected: selected == nil) { selected = nil }
                        ForEach(visible, id: \.id) { option in
                            GitlabEditorOptionTile(title: option.title, selected: selected == option.id) { selected = option.id }
                        }
                        if visible.isEmpty {
                            GitlabEditorMessage(message: options.isEmpty ? appString("taskDetailNoMilestones", "No milestones") : appString("noMatches", "No matches"))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            GitlabEditorFooter(busy: busy, error: error, onSave: save)
        }
        .frame(width: 340, height: 340).background(theme.colors.card)
        .task {
            selected = currentMilestoneId
            loaded = await loadOptions()
        }
    }

    private func save() {
        busy = true; error = nil
        let id = selected
        Task {
            let result = await onSave(id)
            busy = false
            switch result {
            case .success: onClose()
            case .failure(let f): error = f.message
            }
        }
    }
}
