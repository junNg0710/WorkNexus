import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/nav/zentao_module_tree_section.dart
/// The board's module tree in its side panel: "All modules", then the product's (bugs) or execution's (tasks)
/// modules; a pick shows only that module's tickets.
struct ZentaoModuleTreeSection: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState
    /// The bug board, else the task board.
    let bugs: Bool

    var body: some View {
        let board = bugs ? state.bugBoard : state.taskBoard
        let picked = board.filter.modules
        VStack(alignment: .leading, spacing: 0) {
            ScopeGroupHeader(title: appString("zentaoModulesGroup", "Modules"))
            switch state.boardModuleNames(bugs: bugs) {
            case .loaded(let paths):
                let tree = ZentaoNavLogic.moduleTree(bugs: bugs, query: board.boardQuery, bugTab: state.bugTab,
                                                     dueThisWeek: state.dueThisWeek, paths: paths, hideEmpty: state.hideEmptyModules)
                ScopeEntryRow(name: appString("zentaoAllModules", "All modules"), systemImage: "square.stack.3d.up", count: tree.total,
                              selected: picked.isEmpty, onTap: { board.selectModule(nil) })
                ForEach(tree.nodes, id: \.id) { node in
                    // A pick of several (from the Filters popover) marks each.
                    ZentaoModuleRow(node: node, selected: picked.contains(node.id)) { board.selectModule(node.id) }
                }
                if tree.nodes.isEmpty { ZentaoModuleNote(text: appString("zentaoNoModules", "This product has no modules.")) }
            case .failed:
                SidebarStatusRow(label: appString("zentaoModulesUnavailable", "Couldn't load the modules"), isError: true,
                                 onRetry: { state.loadModuleNames(bugs: bugs) })
            case .loading:
                SidebarStatusRow(label: appString("zentaoModulesGroup", "Modules"), loading: true)
            }
        }
        .task(id: ZentaoNavLogic.moduleScopeKey(bugs: bugs, product: state.product, execution: state.execution)) {
            state.loadModuleNames(bugs: bugs)
        }
    }
}

/// A module of the tree, indented under its parents; empty modules read quieter, as ZenTao's own tree greys them.
private struct ZentaoModuleRow: View {
    @Environment(\.appTheme) private var theme
    let node: ZenTaoModuleNode
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        ScopeEntryRow(name: node.name, systemImage: node.depth == 0 ? "folder" : "arrow.turn.down.right", count: node.count,
                      selected: selected, onTap: onTap)
            .padding(.leading, theme.spacing.s12 * CGFloat(node.depth))
            .opacity(node.count == 0 && !selected ? 0.6 : 1)
    }
}

private struct ZentaoModuleNote: View {
    @Environment(\.appTheme) private var theme
    let text: String
    var body: some View {
        Text(text).font(theme.typography.caption).foregroundStyle(theme.colors.tx3).padding(theme.spacing.s8)
    }
}

/// The side panel's foot: hide or show the modules with nothing in them.
struct ZentaoHideEmptyModulesToggle: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState

    var body: some View {
        let c = theme.colors
        let hidden = state.hideEmptyModules
        HoverSurface(onTap: { state.hideEmptyModules.toggle() }, cornerRadius: 0) {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: hidden ? "eye" : "eye.slash").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx3)
                Text(hidden ? appString("zentaoShowEmptyModules", "Show empty modules") : appString("zentaoHideEmptyModules", "Hide empty modules"))
                    .font(theme.typography.caption).foregroundStyle(c.tx2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s8)
        }
        .overlay(alignment: .top) { Divider().overlay(c.line) }
    }
}
