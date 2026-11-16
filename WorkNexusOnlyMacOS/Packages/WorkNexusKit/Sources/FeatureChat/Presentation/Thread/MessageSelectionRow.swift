/// Not in the Flutter app.
import CoreUI
import SwiftUI

/// A message row while "Multiple select" is on: a tick before it, and a click anywhere on the row picks or drops it
/// (the bubble's own clicks are off meanwhile). Off, it is the row as it is.
struct MessageSelectionRow<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let state: ChatThreadState
    let message: ChatMessage
    @ViewBuilder let content: Content

    var body: some View {
        let selecting = state.isSelecting
        let can = selecting && ChatThreadState.canSelect(message)
        let on = can && state.isSelected(message)
        HStack(alignment: .center, spacing: 0) {
            if selecting {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: theme.sizes.icon18))
                    .foregroundStyle(on ? theme.colors.accent : theme.colors.tx3)
                    .padding(.leading, theme.spacing.s12).opacity(can ? 1 : 0)
            }
            content.allowsHitTesting(!selecting)
        }
        .background(on ? theme.colors.accent.opacity(0.08) : Color.clear)
        .overlay {
            if can { Color.clear.contentShape(Rectangle()).onTapGesture { state.toggleSelected(message) } }
        }
    }
}
