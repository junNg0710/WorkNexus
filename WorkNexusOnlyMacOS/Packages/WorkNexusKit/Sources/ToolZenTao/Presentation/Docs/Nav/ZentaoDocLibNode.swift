/// Ported from: lib/tools/zentao/presentation/nav/zentao_doc_lib_node.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// A library in the Docs tree; opened, its documents below it, fetched the first time it opens.
struct ZentaoDocLibNode: View {
    let docs: ZentaoDocsState; let account: Account; let lib: ZenTaoDocLib; let pins: ZenTaoDocPins

    var body: some View {
        let expanded = docs.isExpanded(accountId: account.id, libId: lib.id)
        let pinned = pins.hasLib(lib.id)
        VStack(alignment: .leading, spacing: 0) {
            ZentaoDocTreeRow(systemImage: "books.vertical", label: lib.name,
                             onTap: { docs.toggleExpanded(accountId: account.id, libId: lib.id) },
                             pinned: pinned,
                             pinTooltip: pinned ? appString("docsUnpinLibrary", "Unpin library") : appString("docsPinLibrary", "Pin library"),
                             onPin: { Task { await docs.togglePin(accountId: account.id, lib: lib) } }, expanded: expanded)
            if expanded { ZentaoLibDocs(docs: docs, account: account, lib: lib, pins: pins) }
        }
    }
}

private struct ZentaoLibDocs: View {
    @Environment(\.appTheme) private var theme
    let docs: ZentaoDocsState; let account: Account; let lib: ZenTaoDocLib; let pins: ZenTaoDocPins

    var body: some View {
        let fetch = ZentaoDocFetch.docs(accountId: account.id, libId: lib.id)
        let sync = docs.sync(fetch)
        let list = docs.docLists[ZentaoDocsState.libKey(account.id, lib.id)] ?? []
        let open = docs.openDoc(for: account.id)
        let openId = open?.libId == lib.id ? open?.docId : nil
        VStack(alignment: .leading, spacing: 0) {
            if list.isEmpty {
                SidebarStatusRow(label: sync.isLoading ? appString("docsLoadingDocs", "Loading documents…")
                                 : sync.hasFailed ? appString("docsLibrariesUnavailable", "Can't load libraries")
                                 : appString("docsEmptyLibrary", "No documents in this library"),
                                 loading: sync.isLoading, isError: sync.hasFailed,
                                 onRetry: sync.hasFailed ? { Task { await docs.ensure(fetch, account: account, force: true) } } : nil)
                    .padding(.leading, theme.sizes.icon14 + theme.spacing.s4)
            } else {
                ForEach(list) { doc in ZentaoDocRow(docs: docs, account: account, doc: doc, pins: pins, selected: doc.id == openId) }
            }
        }
        .task { docs.watchLib(accountId: account.id, libId: lib.id); await docs.ensure(fetch, account: account) }
    }
}

/// A document in the tree, under its library or (with `libraryName`) in the pinned group.
struct ZentaoDocRow: View {
    let docs: ZentaoDocsState; let account: Account; let doc: ZenTaoDocSummary; let pins: ZenTaoDocPins; let selected: Bool
    var libraryName: String?

    var body: some View {
        let pinned = pins.hasDoc(doc.id)
        ZentaoDocTreeRow(systemImage: doc.acl == nil || doc.acl == "open" ? "doc.text" : "lock.doc", label: doc.title,
                         subtitle: libraryName, onTap: { docs.open(accountId: account.id, libId: doc.libId, docId: doc.id) },
                         pinned: pinned,
                         pinTooltip: pinned ? appString("docsUnpinDoc", "Unpin document") : appString("docsPinDoc", "Pin document"),
                         onPin: { Task { await docs.togglePin(accountId: account.id, doc: doc) } },
                         indented: libraryName == nil, selected: selected)
    }
}
