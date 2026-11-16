/// Ported from: lib/features/chat/presentation/widgets/message_list_header.dart + scroll_to_latest_button.dart
import CoreUI
import SwiftUI

/// Top of the thread: a spinner while earlier messages load (they load on their own), a retry button after a failed
/// load, or the start marker.
struct MessageListHeaderView: View {
    @Environment(\.appTheme) private var theme
    let reachedStart: Bool
    /// No messages to show: the list's empty state (or a load's spinner) stands in for the marker.
    let isEmpty: Bool
    let failed: Bool
    let onLoadOlder: () -> Void

    var body: some View {
        // An empty chat shows its empty state over the list instead.
        if isEmpty && !failed {
            EmptyView()
        } else if !reachedStart && !failed {
            AppInlineSpinner()
        } else if reachedStart {
            Text(L.beginning).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
                .frame(maxWidth: .infinity).padding(.bottom, theme.spacing.s12)
        } else {
            Button(L.loadOlder, action: onLoadOlder).buttonStyle(.plain).font(theme.typography.metaStrong)
                .foregroundStyle(theme.colors.tx2).frame(maxWidth: .infinity).padding(.bottom, theme.spacing.s12)
        }
    }
}

/// Round button over the bottom of the messages while the user has scrolled up: jumps back to the newest message.
/// `unseen` counts messages that arrived since they scrolled away, shown as a badge on the button.
struct ScrollToLatestButton: View {
    @Environment(\.appTheme) private var theme
    /// Scales in and out as the user leaves and returns to the bottom.
    let visible: Bool
    let unseen: Int
    let action: () -> Void

    var body: some View {
        Group {
            if visible {
                Button(action: action) {
                    Image(systemName: "chevron.down.2").font(.system(size: theme.sizes.icon16, weight: .light))
                        .foregroundStyle(unseen > 0 ? theme.colors.accent : theme.colors.tx2)
                        .frame(width: theme.spacing.s40, height: theme.spacing.s40)
                        .background(theme.colors.panel, in: Circle())
                        .overlay(Circle().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                        .shadow(color: theme.colors.scrim.opacity(0.2), radius: theme.spacing.s4, y: 1)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).pointerStyle(.link)
                .overlay(alignment: .top) { if unseen > 0 { AppCountBadge(unseen).offset(y: -theme.spacing.s6) } }
                .help(unseen > 0 ? L.newMessages(unseen) : L.scrollToLatest)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: theme.motion.base), value: visible)
    }
}
