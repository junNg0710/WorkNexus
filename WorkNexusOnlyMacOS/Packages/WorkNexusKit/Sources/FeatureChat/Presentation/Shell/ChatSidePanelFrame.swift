import CoreUI
import SwiftUI

/// The frame of a panel beside the chat: a titled header with a back and/or close button above the content. Esc closes it
/// (or steps back to the info).
/// Ported from: lib/features/chat/presentation/widgets/chat_side_panel_frame.dart
struct ChatSidePanelFrame<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    var width: CGFloat = ChatShellLayout.sidePanelWidth
    var onBack: (() -> Void)?
    var onClose: (() -> Void)?
    /// Hides the panel column (the info panel with room): an icon at the head of the header, the other end of the
    /// header's own "show chat info" toggle.
    var onCollapse: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s4) {
                if let onCollapse {
                    AppIconButton(AppPanelIcon.collapse(.trailing), help: shellString("chatHideInfo", "Hide chat info"), action: onCollapse)
                }
                if let onBack { AppIconButton("arrow.left", help: shellString("chatBackToInfo", "Back to chat info"), action: onBack) }
                Text(title).font(theme.typography.title).foregroundStyle(theme.colors.tx).lineLimit(1)
                    .padding(.leading, onBack == nil && onCollapse == nil ? theme.spacing.s12 : 0)
                Spacer(minLength: 0)
                if let onClose { AppIconButton("xmark", help: shellString("chatClosePanel", "Close"), action: onClose) }
            }
            .padding(.horizontal, theme.spacing.s12)
            .frame(height: ChatShellLayout.headerHeight)
            .background(theme.colors.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width)
        .background(theme.colors.bg)
        .overlay(alignment: .leading) { Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline) }
        .onExitCommand { (onClose ?? onBack)?() }
    }
}

/// One section of a panel: a surface card with a hairline border.
/// Ported from: lib/features/chat/presentation/widgets/chat_side_panel_frame.dart
struct ChatPanelCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    var padding: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding ?? theme.spacing.s12).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.panel, in: RoundedRectangle(cornerRadius: theme.radii.lg))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .padding(.bottom, theme.spacing.s8)
    }
}

/// The open chat with a panel: beside the messages when they keep their minimum width, else slid over them from the right
/// (squeezing them would wrap text a few letters per line). Over the messages, a click outside the panel dismisses it.
/// Ported from: lib/features/chat/presentation/widgets/chat_side_panel_host.dart
struct ChatSidePanelHost<Messages: View, Panel: View>: View {
    @Environment(\.appTheme) private var theme
    let infoRoom: Bool
    let showsPanel: Bool
    let onDismiss: () -> Void
    @ViewBuilder let messages: Messages
    @ViewBuilder let panel: Panel

    var body: some View {
        // `messages` stays the first child in both layouts: moved in the tree, the list would lose its scroll position.
        HStack(spacing: 0) {
            messages
            if infoRoom && showsPanel { panel }
        }
        .overlay(alignment: .trailing) {
            if !infoRoom && showsPanel {
                ZStack(alignment: .trailing) {
                    theme.colors.scrim.opacity(0.18).onTapGesture(perform: onDismiss)
                    panel.shadow(color: theme.colors.scrim.opacity(0.18), radius: theme.spacing.s24)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: theme.motion.base), value: showsPanel)
    }
}

/// Dialog content that takes the height it needs and scrolls only when it would exceed `maxHeight`.
struct FitOrScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.frame(maxHeight: maxHeight)
        }
    }
}
