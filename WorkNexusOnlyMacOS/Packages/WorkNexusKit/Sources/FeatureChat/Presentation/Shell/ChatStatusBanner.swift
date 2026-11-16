import CoreDomain
import CoreUI
import SwiftUI

/// A strip above the chat explaining why it is not live, with the action that fixes it. Hidden while online.
/// Ported from: lib/features/chat/presentation/widgets/chat_status_banner.dart
struct ChatStatusBanner: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel

    var body: some View {
        if let (text, tone, withConnect) = content {
            HStack {
                Text(text).font(theme.typography.meta).foregroundStyle(tone)
                Spacer(minLength: theme.spacing.s8)
                if withConnect { AppButton(shellString("chatConnect", "Connect")) { model.connect() } }
            }
            .padding(.horizontal, theme.spacing.s20).padding(.vertical, theme.spacing.s8)
            .background(theme.colors.panel2)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        }
    }

    private var content: (String, Color, Bool)? {
        switch model.status {
        case nil, .online?, .needsTrust?: nil
        case .connecting?: (shellString("chatConnecting", "Connecting to ZenTao chat…"), theme.colors.tx2, false)
        case .reconnecting(let retryIn, _)?:
            (shellString("chatReconnecting", "Connection lost — retrying in {seconds}s", ["seconds": "\(Int(retryIn))"]), theme.colors.amber, false)
        case .offline?: (shellString("chatConnectionOffline", "Chat is offline"), theme.colors.tx2, true)
        case .signedOut(let message, let kicked)?:
            (kicked ? shellString("chatKicked", "Signed out because this account signed in somewhere else.")
                : shellString("chatSignedOut", "Chat signed out: {reason}", ["reason": message]), theme.colors.red, true)
        }
    }
}

/// A warning strip above the chat while message notifications are on in the app but blocked by the OS; the host drives it
/// through `ChatShellEvents` (the OS side is the host's).
/// Ported from: lib/features/chat/presentation/widgets/chat_notification_banner.dart
struct ChatNotificationBanner: View {
    @Environment(\.appTheme) private var theme
    let events: ChatShellEvents
    @State private var dismissed = false

    var body: some View {
        if events.notificationsBlocked && !dismissed {
            HStack(spacing: theme.spacing.s12) {
                Image(systemName: "bell.slash").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.amber)
                Text(shellString("chatNotificationsBlocked",
                                 "Notifications are turned off for WorkNexus in System Settings, so you won't be alerted to new messages."))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx)
                Spacer(minLength: theme.spacing.s8)
                AppButton(shellString("chatNotificationsAllow", "Turn on")) { events.onEnableNotifications?() }
                AppIconButton("xmark", help: shellString("chatDismiss", "Dismiss")) { dismissed = true }
            }
            .padding(.horizontal, theme.spacing.s20).padding(.vertical, theme.spacing.s8)
            .background(theme.colors.amber.opacity(0.12))
            .background(theme.colors.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        }
    }
}
