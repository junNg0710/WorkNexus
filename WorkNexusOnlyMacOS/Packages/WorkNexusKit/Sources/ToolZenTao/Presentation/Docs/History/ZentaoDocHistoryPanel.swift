/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_history_panel.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A document's history, as ZenTao's web lists it: numbered entries down a line - when, who, what - each with what
/// changed one tap away.
struct ZentaoDocHistoryPanel: View {
    @Environment(\.appTheme) private var theme
    let docs: ZentaoDocsState; let account: Account; let docId: String; let onClose: () -> Void

    var body: some View {
        let fetch = ZentaoDocFetch.history(accountId: account.id, docId: docId)
        let sync = docs.sync(fetch)
        let entries = docs.history(accountId: account.id, docId: docId)
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s4) {
                Text(appString("docsHistory", "History")).font(theme.typography.title).foregroundStyle(theme.colors.tx)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZentaoDocToolButton(systemImage: "arrow.clockwise", help: appString("retry", "Retry"), loading: sync.isLoading) {
                    Task { await docs.ensure(fetch, account: account, force: true) }
                }
                ZentaoDocToolButton(systemImage: "xmark", help: appString("close", "Close"), action: onClose)
            }
            .padding(EdgeInsets(top: theme.spacing.s8, leading: theme.spacing.s12, bottom: theme.spacing.s6, trailing: theme.spacing.s6))
            if !entries.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                            ZentaoDocHistoryEntry(number: i + 1, entry: e, last: i == entries.count - 1, dateFormat: docs.settings.dateFormat)
                        }
                    }
                    .padding(EdgeInsets(top: theme.spacing.s4, leading: theme.spacing.s12, bottom: theme.spacing.s12, trailing: theme.spacing.s8))
                }
            } else if sync.isLoading {
                AppStateView(.loading)
            } else if sync.hasFailed {
                AppStateView(.error(appString("docsHistoryUnavailable", "Couldn't load the history"))) {
                    Task { await docs.ensure(fetch, account: account, force: true) }
                }
            } else {
                AppStateView(.empty(appString("docsHistoryEmpty", "No history yet")))
            }
        }
        .background(theme.colors.card)
        .task(id: docId) { await docs.observeHistory(accountId: account.id, docId: docId) }
        .task(id: docId) { await docs.ensure(fetch, account: account) }
    }
}
