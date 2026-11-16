/// Ported from: lib/tools/zentao/presentation/sections/zentao_docs_section.dart
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// The L5 viewport of the Docs section: the open document across the whole viewport. Libraries and their documents are
/// picked in the nav pane's tree (`ZentaoDocLibsPane`); the open document is kept per account (`ZentaoDocsState`), so it
/// is still open after a trip to Tasks or Bugs.
public struct ZentaoDocsSection: View {
    let deps: ZentaoDependencies; let docs: ZentaoDocsState; let account: Account; let location: ToolLocation
    public init(deps: ZentaoDependencies, docs: ZentaoDocsState, account: Account, location: ToolLocation) {
        self.deps = deps; self.docs = docs; self.account = account; self.location = location
    }

    public var body: some View {
        Group {
            if let open = docs.openDoc(for: account.id) {
                ZentaoDocViewer(docs: docs, account: account, docId: open.docId).id(open.docId)
            } else {
                AppStateView(.empty(appString("docsPickDocument", "Pick a document in the list on the left.")))
            }
        }
        .task { docs.start() }
    }
}
