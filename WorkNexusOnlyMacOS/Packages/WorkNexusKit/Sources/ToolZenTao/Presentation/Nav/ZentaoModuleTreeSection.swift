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
    /// Where a module is being added: inside the module of this id, or at the top (`ZentaoModuleAddRow.top`).
    @State private var addingIn: String?

    var body: some View {
        let board = bugs ? state.bugBoard : state.taskBoard
        let picked = board.filter.modules
        let names = state.boardModuleNames(bugs: bugs)
        VStack(alignment: .leading, spacing: 0) {
            ZentaoModuleHeader(reloading: state.isReloadingModules(bugs: bugs), canAdd: names.value != nil,
                               onReload: { state.reloadModuleNames(bugs: bugs) }, onAdd: { addingIn = ZentaoModuleAddRow.top })
            switch names {
            case .loaded(let paths):
                let tree = ZentaoNavLogic.moduleTree(bugs: bugs, query: board.boardQuery, bugTab: state.bugTab,
                                                     leader: state.leader(bugs: bugs), names: state.memberNames, paths: paths, hideEmpty: state.hideEmptyModules)
                ScopeEntryRow(name: appString("zentaoAllModules", "All modules"), systemImage: "square.stack.3d.up", count: tree.total,
                              selected: picked.isEmpty, onTap: { board.selectModule(nil) })
                if addingIn == ZentaoModuleAddRow.top {
                    ZentaoModuleAddRow(state: state, bugs: bugs, parentId: nil, depth: 0) { addingIn = nil }
                }
                ForEach(tree.nodes, id: \.id) { node in
                    // A pick of several (from the Filters popover) marks each.
                    ZentaoModuleRow(node: node, selected: picked.contains(node.id)) { board.selectModule(node.id) }
                        .contextMenu {
                            Button { addingIn = node.id } label: {
                                Label(appString("zentaoAddModuleInside", "Add a module inside…"), systemImage: "folder.badge.plus")
                            }
                        }
                    if addingIn == node.id {
                        ZentaoModuleAddRow(state: state, bugs: bugs, parentId: node.id, depth: node.depth + 1) { addingIn = nil }
                    }
                }
                if tree.nodes.isEmpty, addingIn == nil { ZentaoModuleNote(text: appString("zentaoNoModules", "This product has no modules.")) }
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

/// The tree's heading: its title, then "read the list again" and "add a module".
private struct ZentaoModuleHeader: View {
    @Environment(\.appTheme) private var theme
    let reloading: Bool
    let canAdd: Bool
    let onReload: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScopeGroupHeader(title: appString("zentaoModulesGroup", "Modules"))
            if reloading {
                ProgressView().controlSize(.small).frame(width: theme.sizes.icon24, height: theme.sizes.icon24)
            } else {
                ZentaoModuleHeaderButton(systemImage: "arrow.clockwise", help: appString("zentaoReloadModules", "Read the modules again"),
                                         action: onReload)
            }
            if canAdd {
                ZentaoModuleHeaderButton(systemImage: "plus", help: appString("zentaoAddModule", "Add a module"), action: onAdd)
            }
        }
    }
}

/// A small icon button of the heading (the pane is too narrow for the usual one).
private struct ZentaoModuleHeaderButton: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: theme.sizes.icon12, weight: .medium))
                .foregroundStyle(hovering ? theme.colors.tx : theme.colors.tx2)
                .frame(width: theme.sizes.icon24, height: theme.sizes.icon24)
                .background(hovering ? theme.colors.tx.opacity(0.08) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.help(help)
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
