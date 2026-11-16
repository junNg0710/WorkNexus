import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/widgets/zentao_popover_tree_node.dart
/// A project in the execution picker: a container - tapping it opens or closes its executions, which are what the
/// user picks (a project is never selected). It opens by itself while it holds the open execution, or while a search
/// is typed; `onExpand` asks for its executions each time it opens.
struct ZentaoProjectNode: View {
    @Environment(\.appTheme) private var theme
    let choice: ZentaoProjectChoice
    let openExecutionId: String?
    let openProjectId: String?
    var expandedByDefault = false
    let executions: ZentaoLoad<[ProviderExecution]>?
    let onExpand: () -> Void
    let onSelect: (ProviderExecution) -> Void
    @State private var expanded: Bool

    init(choice: ZentaoProjectChoice, openExecutionId: String?, openProjectId: String?, expandedByDefault: Bool = false,
         executions: ZentaoLoad<[ProviderExecution]>?, onExpand: @escaping () -> Void, onSelect: @escaping (ProviderExecution) -> Void) {
        self.choice = choice; self.openExecutionId = openExecutionId; self.openProjectId = openProjectId
        self.expandedByDefault = expandedByDefault; self.executions = executions; self.onExpand = onExpand; self.onSelect = onSelect
        _expanded = State(initialValue: expandedByDefault || openProjectId == choice.id)
    }

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 0) {
            HoverSurface(onTap: { expanded.toggle() }, cornerRadius: theme.radii.xs) {
                HStack(spacing: theme.spacing.s6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: theme.sizes.icon12))
                        .foregroundStyle(c.tx3).frame(width: theme.sizes.icon14)
                    Image(systemName: "folder").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx2)
                    Text(choice.project.name).font(theme.typography.meta).foregroundStyle(c.tx).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if choice.openCount > 0 { Text("\(choice.openCount)").font(theme.typography.mono.weight(.semibold)).foregroundStyle(c.tx3) }
                    ZentaoKindTag(text: appString("project", "Project"))
                }
                .padding(.horizontal, theme.spacing.s4).padding(.vertical, theme.spacing.s6)
            }
            if expanded {
                ZentaoProjectExecutions(executions: executions, openExecutionId: openExecutionId, onSelect: onSelect)
            }
        }
        // The project of the open execution unfolds when the open execution moves into it.
        .onChange(of: openProjectId) { _, new in if new == choice.id { expanded = true } }
        .task(id: expanded) { if expanded { onExpand() } }
    }
}

/// The executions under an open project: its rows, a spinner while they load, or a quiet note.
private struct ZentaoProjectExecutions: View {
    @Environment(\.appTheme) private var theme
    let executions: ZentaoLoad<[ProviderExecution]>?
    let openExecutionId: String?
    let onSelect: (ProviderExecution) -> Void

    var body: some View {
        let c = theme.colors
        switch executions {
        case .loaded(let list) where list.isEmpty:
            ZentaoNodeNote(text: appString("noExecutions", "No executions"))
        case .loaded(let list):
            VStack(spacing: theme.spacing.s2) {
                ForEach(list) { e in ZentaoExecutionItem(execution: e, selected: e.id == openExecutionId) { onSelect(e) } }
            }
        case .failed:
            ZentaoNodeNote(text: appString("executionsUnavailable", "Can't load executions"))
        case .loading, nil:
            ProgressView().controlSize(.mini).tint(c.accent)
                .padding(.leading, theme.spacing.s24 + theme.spacing.s8).padding(.vertical, theme.spacing.s4)
        }
    }
}

/// An execution under a project: a dot and its name.
private struct ZentaoExecutionItem: View {
    @Environment(\.appTheme) private var theme
    let execution: ProviderExecution
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onTap, selected: selected, cornerRadius: theme.radii.xs) {
            HStack(spacing: theme.spacing.s8) {
                Circle().fill(c.accent.opacity(selected ? 1 : 0.7)).frame(width: theme.spacing.s6, height: theme.spacing.s6)
                Text(execution.name).font(theme.typography.mono.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? c.accent : c.tx).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, theme.spacing.s24 + theme.spacing.s4).padding(.trailing, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
        }
    }
}

private struct ZentaoNodeNote: View {
    @Environment(\.appTheme) private var theme
    let text: String
    var body: some View {
        Text(text).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
            .padding(.leading, theme.spacing.s24 + theme.spacing.s8).padding(.vertical, theme.spacing.s2)
    }
}
