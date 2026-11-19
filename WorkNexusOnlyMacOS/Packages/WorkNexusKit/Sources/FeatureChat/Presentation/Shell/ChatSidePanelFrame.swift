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
                    AppIconButton(panel: .collapse, side: .trailing, help: shellString("chatHideInfo", "Hide chat info"), perform: onCollapse)
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
///
/// A panel opening slides in; over the messages it also slides out, with the scrim fading. Beside the messages it takes its
/// room at once and only its contents move, so the messages are laid out once, not on every frame of the slide.
/// Ported from: lib/features/chat/presentation/widgets/chat_side_panel_host.dart
struct ChatSidePanelHost<Messages: View, Panel: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let infoRoom: Bool
    let showsPanel: Bool
    let onDismiss: () -> Void
    @ViewBuilder let messages: Messages
    @ViewBuilder let panel: Panel
    /// Set once the chat is on screen: a panel there from the start (the info column) shows as it is, without sliding in.
    @State private var settled = false
    /// `infoRoom` as of the last update: a panel that comes beside the messages because the window got wide enough
    /// shows at once; only one the user opens slides in.
    @State private var lastInfoRoom: Bool?

    var body: some View {
        // `messages` stays the first child in both layouts: moved in the tree, the list would lose its scroll position.
        HStack(spacing: 0) {
            messages
            if infoRoom && showsPanel {
                panel.modifier(ChatPanelEntrance(animate: settled && !reduceMotion && (lastInfoRoom ?? infoRoom) == infoRoom))
            }
        }
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                if !infoRoom && showsPanel {
                    theme.colors.scrim.opacity(Self.scrimAlpha).onTapGesture(perform: onDismiss).transition(.opacity)
                    panel.shadow(color: theme.colors.scrim.opacity(Self.scrimAlpha), radius: theme.spacing.s24)
                        .transition(.move(edge: .trailing))
                }
            }
            // Only the overlay animates: in, at the panels' pace; out, at the shorter one.
            .animation(reduceMotion ? nil : showsPanel ? .easeOut(duration: theme.motion.slow) : .easeIn(duration: theme.motion.base),
                       value: showsPanel)
        }
        .onAppear { settled = true; lastInfoRoom = infoRoom }
        .onChange(of: infoRoom) { _, now in lastInfoRoom = now }
    }

    /// How much the messages are dimmed under a panel drawn over them.
    static var scrimAlpha: Double { 0.18 }
}

/// A panel beside the messages easing in: from a little toward the window's edge, fading in. Decided once, when it appears.
private struct ChatPanelEntrance: ViewModifier {
    @Environment(\.appTheme) private var theme
    @State private var shown: Bool

    init(animate: Bool) { _shown = State(initialValue: !animate) }

    /// How far (of the panel's width) it slides.
    static var slide: CGFloat { 0.08 }

    func body(content: Content) -> some View {
        content
            .visualEffect { [shown] effect, proxy in effect.offset(x: shown ? 0 : proxy.size.width * Self.slide) }
            .opacity(shown ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                withAnimation(.easeOut(duration: theme.motion.slow)) { shown = true }
            }
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
