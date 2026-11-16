/// Ported from: lib/tools/zentao/presentation/nav/zentao_doc_libs_scope_list.dart
import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// The nav pane's body while Docs is open: one tree of the account's libraries, each opening onto its documents, under
/// the pinned libraries and documents. Libraries are flat (the server sends no space for them); the filter narrows them
/// by name, and the pins by name or title.
public struct ZentaoDocLibsPane: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let docs: ZentaoDocsState; let account: Account; let location: ToolLocation
    public init(deps: ZentaoDependencies, docs: ZentaoDocsState, account: Account, location: ToolLocation) {
        self.deps = deps; self.docs = docs; self.account = account; self.location = location
    }

    public var body: some View {
        let id = account.id
        let fetch = ZentaoDocFetch.libs(accountId: id)
        let sync = docs.sync(fetch)
        Group {
            if let libs = docs.libs[id], !libs.isEmpty {
                tree(libs: libs, pins: docs.pins[id] ?? ZenTaoDocPins())
            } else {
                Group {
                    if sync.hasFailed {
                        SidebarStatusRow(label: appString("docsLibrariesUnavailable", "Can't load libraries"), isError: true,
                                         onRetry: { Task { await docs.ensure(fetch, account: account, force: true) } })
                    } else {
                        SidebarStatusRow(label: sync.isLoading ? appString("docsLoadingLibraries", "Loading libraries…")
                                         : appString("docsNoLibraries", "No document libraries"), loading: sync.isLoading)
                    }
                }
                .padding(theme.spacing.s8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task { docs.start(); docs.watchAccount(id); await docs.ensure(fetch, account: account) }
    }

    private func tree(libs: [ZenTaoDocLib], pins: ZenTaoDocPins) -> some View {
        let filter = docs.filter(for: account.id)
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = FilterZenTaoDocLibs()(libs, query: filter)
        let pinnedLibs = FilterZenTaoDocLibs()(pins.libs, query: filter)
        let pinnedDocs = pins.docs.filter { query.isEmpty || $0.title.lowercased().contains(query) }
        let libName = Dictionary(libs.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let open = docs.openDoc(for: account.id)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScopeFilterField(text: Binding(get: { docs.filter(for: account.id) }, set: { docs.setFilter($0, accountId: account.id) }),
                                 prompt: appString("docsFilterLibraries", "Filter libraries"))
                ZentaoDocToolButton(systemImage: AppPanelIcon.collapse(.leading), help: appString("paneCollapse", "Collapse sidebar"), small: true) {
                    docs.setPane(collapsed: true, accountId: account.id, section: location.section)
                }
                .padding(.trailing, theme.spacing.s6)
            }
            .padding(.top, theme.spacing.s6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !pinnedDocs.isEmpty || !pinnedLibs.isEmpty {
                        ScopeGroupHeader(title: appString("pinned", "Pinned"))
                        ForEach(pinnedDocs) { doc in
                            ZentaoDocRow(docs: docs, account: account, doc: doc, pins: pins,
                                         selected: doc.id == open?.docId && doc.libId == open?.libId, libraryName: libName[doc.libId] ?? "")
                        }
                        ForEach(pinnedLibs) { lib in ZentaoDocLibNode(docs: docs, account: account, lib: lib, pins: pins) }
                        Color.clear.frame(height: theme.spacing.s8)
                    }
                    ScopeGroupHeader(title: appString("docsLibrariesGroup", "Libraries"))
                    if filtered.isEmpty {
                        SidebarStatusRow(label: appString("docsNoLibraries", "No document libraries"))
                    } else {
                        ForEach(filtered.filter { !pins.hasLib($0.id) }) { lib in
                            ZentaoDocLibNode(docs: docs, account: account, lib: lib, pins: pins)
                        }
                    }
                }
                .padding(EdgeInsets(top: theme.spacing.s4, leading: theme.spacing.s6, bottom: theme.spacing.s16, trailing: theme.spacing.s6))
            }
        }
    }
}
