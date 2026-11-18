/// Ported from: lib/features/chat/presentation/widgets/pinned_message_bar.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Under the chat header: the most recently pinned message and how many others are pinned. Tap lists them all beside the
/// chat, as cards. Reads `state.chat.pinnedMessageIds`; draws nothing while nothing is pinned.
public struct PinnedMessageBar: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let state: ChatThreadState
    @State private var message: ChatMessage?

    public init(state: ChatThreadState) { self.state = state }

    public var body: some View {
        if let latest = state.chat.pinnedMessageIds.last {
            let others = state.chat.pinnedMessageIds.count - 1
            HStack(spacing: theme.spacing.s10) {
                Image(systemName: "text.bubble").font(.system(size: theme.sizes.icon20)).foregroundStyle(theme.colors.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L.pinnedBarTitle).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                    Text(preview).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2).lineLimit(1).truncationMode(.tail)
                        .chatPrivacyFade()
                }
                Spacer(minLength: theme.spacing.s8)
                if others > 0 {
                    Button { state.sidePanel = .pinned } label: {
                        HStack(spacing: theme.spacing.s4) {
                            Text(L.morePins(others)); Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12))
                        }
                        .font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
                        .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s4)
                        .overlay(Capsule().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                    }
                    .buttonStyle(.plain)
                }
                PinnedBarMenu(state: state, serverId: latest, message: message)
            }
            .padding(.leading, theme.spacing.s20).padding(.trailing, theme.spacing.s10)
            .frame(height: 48).background(theme.colors.panel)
            .overlay(alignment: .bottom) { theme.colors.line.frame(height: theme.borders.hairline) }
            .contentShape(Rectangle())
            .onTapGesture { state.sidePanel = .pinned }
            .task(id: latest) { await watch(latest) }
        }
    }

    private var preview: String {
        guard let m = message else { return "…" }
        return "\(ChatTextLabels.userName(state.users, m.senderId)): \(ChatTextLabels.preview(m))"
    }

    private func watch(_ serverId: Int) async {
        guard let chat = services?.chat else { return }
        var requested = false
        for await m in chat.watchMessage(accountId: state.accountId, chatGid: state.chatGid, serverId: serverId) {
            message = m
            if m == nil, !requested {
                requested = true
                _ = await FetchChatMessages(chat)(accountId: state.accountId, chatGid: state.chatGid, serverIds: [serverId])
            }
        }
    }
}

/// The bar's "…": jump to the pinned message, or unpin it.
private struct PinnedBarMenu: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.toasts) private var toasts
    let state: ChatThreadState
    let serverId: Int
    let message: ChatMessage?

    var body: some View {
        Menu {
            Button { state.requestJump(to: serverId) } label: { Label(L.viewOriginal, systemImage: "arrowshape.turn.up.right") }
            if let services, let message, PinChatMessage(services.chat).canPin(state.chat, selfUserId: state.selfUserId, selfAccount: state.selfAccount) {
                Button(role: .destructive) {
                    Task { @MainActor in
                        if case .failure(let f) = await PinChatMessage(services.chat)(message, pinned: false) { toasts?.show(f.message, kind: .error) }
                    }
                } label: { Label(L.unpin, systemImage: "pin.slash") }
            }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(theme.colors.tx2).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help(L.moreActions)
    }
}
