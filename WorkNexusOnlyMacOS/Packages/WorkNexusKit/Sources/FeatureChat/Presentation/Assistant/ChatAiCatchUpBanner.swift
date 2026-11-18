/// Ported from: lib/features/chat/presentation/widgets/chat_ai_catch_up_banner.dart
import CoreUI
import SwiftUI

/// A strip over the messages of a chat opened with many unread ones, offering an AI summary of them. Gone once dismissed or
/// once the summary is asked for, until the chat is opened again.
struct ChatAiCatchUpBanner: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.chatSettings) private var settings
    let session: ChatThreadSession

    var body: some View {
        let assistant = session.assistant
        if let services, services.ai != nil, assistant.offersCatchUp {
            let unread = assistant.unreadOnOpen
            HStack(spacing: theme.spacing.s12) {
                Image(systemName: "sparkles").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.accent)
                Text(appFormat("chatAiCatchUp", "%1$@ new messages since you last looked", "\(unread)"))
                    .font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
                Spacer(minLength: theme.spacing.s8)
                AppButton(appString("chatAiCatchUpAction", "Summarize"), systemImage: "sparkles", kind: .primary) {
                    let context = ChatAiContext(services: services, settings: settings, state: session.state)
                    Task {
                        await assistant.summarize(ChatSummaryScope(unread: true, count: unread), context: context,
                                                  onStart: { assistant.catchUpDismissed = true })
                    }
                }
                AppIconButton("xmark", help: appString("chatAiDismiss", "Dismiss")) { assistant.catchUpDismissed = true }
            }
            .padding(EdgeInsets(top: theme.spacing.s8, leading: theme.spacing.s24, bottom: theme.spacing.s8, trailing: theme.spacing.s8))
            .background(theme.colors.accent.opacity(0.08))
            .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        }
    }
}
