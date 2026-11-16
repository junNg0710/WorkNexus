import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/labels_editor.dart
/// Pure rules of the label picker (testable without a view).
enum GitlabLabelSelection {
    /// The labels matching the search box.
    static func visible(_ options: [ProviderLabelOption], query: String) -> [ProviderLabelOption] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? options : options.filter { $0.name.lowercased().contains(q) }
    }

    /// The labels to save: `selected` in the order the project lists them, then any kept label it no longer lists.
    static func ordered(_ selected: Set<String>, options: [ProviderLabelOption]) -> [String] {
        let known = options.map(\.name).filter(selected.contains)
        return known + selected.subtracting(known).sorted()
    }
}

/// A searchable multi-select of the project's labels with a Save footer.
struct GitlabLabelsEditor: View {
    @Environment(\.appTheme) private var theme
    let currentLabels: [String]
    let loadOptions: () async -> Outcome<[ProviderLabelOption]>
    let onSave: ([String]) async -> Outcome<Void>
    let onClose: () -> Void
    @State private var loaded: Outcome<[ProviderLabelOption]>?
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            GitlabEditorSearchField(text: $query, hint: appString("searchLabels", "Search labels…"))
            switch loaded {
            case nil: AppStateView(.loading)
            case .failure(let f)?: AppStateView(.error(f.message))
            case .success(let options)?:
                let visible = GitlabLabelSelection.visible(options, query: query)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if visible.isEmpty {
                            GitlabEditorMessage(message: options.isEmpty ? appString("noProjectLabels", "No project labels") : appString("noMatches", "No matches"))
                        }
                        ForEach(visible, id: \.name) { option in
                            GitlabEditorOptionTile(title: option.name, selected: selected.contains(option.name),
                                                   leading: AnyView(GitlabLabelSwatch(hex: option.color))) {
                                if selected.contains(option.name) { selected.remove(option.name) } else { selected.insert(option.name) }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            GitlabEditorFooter(busy: busy, error: error, onSave: save)
        }
        .frame(width: 340, height: 380).background(theme.colors.card)
        .task {
            selected = Set(currentLabels)
            loaded = await loadOptions()
        }
    }

    private func save() {
        busy = true; error = nil
        let labels = GitlabLabelSelection.ordered(selected, options: loaded?.value ?? [])
        Task {
            let result = await onSave(labels)
            busy = false
            switch result {
            case .success: onClose()
            case .failure(let f): error = f.message
            }
        }
    }
}

/// The colour dot of a label (the provider's colour, else the accent).
private struct GitlabLabelSwatch: View {
    @Environment(\.appTheme) private var theme
    let hex: String?
    var body: some View {
        Circle().fill(ProviderColor.argb(fromHex: hex).map { Color(argb: $0) } ?? theme.colors.accent)
            .frame(width: theme.spacing.s12, height: theme.spacing.s12)
    }
}
