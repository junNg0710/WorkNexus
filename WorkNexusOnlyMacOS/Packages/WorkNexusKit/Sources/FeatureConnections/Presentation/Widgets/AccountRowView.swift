import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/widgets/account_row.dart
/// One connected account: provider, handle, the server it talks to (and the GitLab version once probed), and
/// its sync / remove actions.
struct AccountRowView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var version: String?
    @State private var confirmRemove = false
    let account: Account
    let model: ConnectionsModel
    let first: Bool

    /// The instance the account talks to, without a trailing slash; nil when none is recorded.
    static func serverUrl(_ baseUrl: String?) -> String? {
        let url = (baseUrl ?? "").trimmed
        if url.isEmpty { return nil }
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    var body: some View {
        let c = theme.colors, s = theme.spacing
        HStack(spacing: s.s16) {
            BrandLogoBadge(account.providerType, size: theme.sizes.icon24)
            VStack(alignment: .leading, spacing: s.s2) {
                HStack(spacing: s.s8) {
                    Text(account.handle).font(theme.typography.mono.weight(.semibold)).foregroundStyle(c.tx).lineLimit(1)
                    Text(account.providerType.displayName).font(theme.typography.caption).foregroundStyle(c.tx3)
                    if let version { Text("v\(version)").font(theme.typography.caption).foregroundStyle(c.tx3) }
                }
                if let url = Self.serverUrl(account.baseUrl) {
                    Text(url).font(theme.typography.mono).foregroundStyle(c.tx3).lineLimit(1).help(url)
                }
            }
            Spacer(minLength: 0)
            Circle().fill(c.green).frame(width: s.s8, height: s.s8)
            Text(L.connected).font(theme.typography.meta).foregroundStyle(c.tx2)
            // Only a live account (one with a stored secret) can sync or be removed in place.
            if account.credentialsRef != nil {
                AppIconButton("arrow.triangle.2.circlepath", help: L.syncNow, action: sync)
                AppIconButton("trash", help: L.removeAccount) { confirmRemove = true }
            }
        }
        .padding(.horizontal, s.s20).padding(.vertical, s.s16)
        .overlay(alignment: .top) { if !first { Rectangle().fill(c.line).frame(height: theme.borders.hairline) } }
        .appConfirmDialog(isPresented: $confirmRemove, title: L.removeAccountTitle(account.handle),
                          message: L.removeAccountMessage, confirmLabel: L.removeConfirm, destructive: true) {
            Task { await model.remove(account) }
        }
        .task(id: account.id) { version = await model.serverVersion(of: account) }
    }

    private func sync() {
        toasts?.show(L.syncing(account.handle))
        Task {
            switch await model.sync(account) {
            case .synced(let n): toasts?.show(L.synced(n, account.handle))
            case .failed(let m): toasts?.show(L.syncFailed(account.handle, m), kind: .error)
            }
        }
    }
}
