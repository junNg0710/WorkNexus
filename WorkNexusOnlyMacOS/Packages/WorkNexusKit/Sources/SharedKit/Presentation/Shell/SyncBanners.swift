import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/app/shell/auth_expired_banner.dart. A strip across the top of a section: warning tint, an icon, the
/// message, and an optional action button. Used for the expired session (Re-authenticate), the offline / sync-failed strips
/// and, by tool sections, for a failed slice fetch (`SectionNoticeBanner`).
public struct SectionNoticeBanner: View {
    public enum Tone { case warning, error, info }
    @Environment(\.appTheme) private var theme
    let tone: Tone; let message: String; let actionTitle: String?; let action: (() -> Void)?; let onDismiss: (() -> Void)?

    public init(tone: Tone = .warning, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil,
                onDismiss: (() -> Void)? = nil) {
        self.tone = tone; self.message = message; self.actionTitle = actionTitle; self.action = action; self.onDismiss = onDismiss
    }

    public var body: some View {
        let tint = tone == .error ? theme.colors.red : (tone == .info ? theme.colors.accent : theme.colors.amber)
        HStack(spacing: theme.spacing.s10) {
            Image(systemName: tone == .error ? "exclamationmark.octagon" : (tone == .info ? "info.circle" : "exclamationmark.triangle"))
                .font(.system(size: theme.sizes.icon16)).foregroundStyle(tint)
            Text(message).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action { AppButton(actionTitle, kind: .secondary, action: action) }
            if let onDismiss { AppIconButton("xmark", help: appString("close", "Close"), action: onDismiss) }
        }
        .padding(.horizontal, theme.spacing.s16).padding(.vertical, theme.spacing.s8)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { Rectangle().fill(tint.opacity(0.3)).frame(height: theme.borders.hairline) }
    }
}

/// The strips of one account's section, from `SectionHealth`: the expired-session banner (opens the connect dialog) and the
/// dismissible offline / failed-sync strip (Retry syncs again).
struct AccountBanners: View {
    let model: ShellModel
    let account: Account
    let health: SectionHealth
    @State private var dismissed: String?

    var body: some View {
        switch health {
        case .healthy: EmptyView()
        case .authExpired:
            SectionNoticeBanner(message: appFormat("sessionExpiredBanner",
                                                    "Your %1$@ session expired. Cached data is read-only until you sign in again.",
                                                    account.providerType.displayName),
                                actionTitle: appString("reauthenticate", "Re-authenticate")) { model.connectRequested = true }
        case .offline where !health.blocksSection && dismissed != health.newsKey:
            SectionNoticeBanner(message: appString("syncOfflineBanner", "You're offline. Showing what was saved on this device."),
                                actionTitle: appString("retry", "Retry"), action: retry, onDismiss: { dismissed = health.newsKey })
        case .failed(let message, false) where dismissed != health.newsKey:
            SectionNoticeBanner(tone: .error, message: appFormat("syncFailedBanner", "Couldn't sync %1$@: %2$@", account.handle, message),
                                actionTitle: appString("retry", "Retry"), action: retry, onDismiss: { dismissed = health.newsKey })
        default: EmptyView()
        }
    }

    private func retry() { Task { _ = await model.services.sync.sync(accountId: account.id) } }
}
