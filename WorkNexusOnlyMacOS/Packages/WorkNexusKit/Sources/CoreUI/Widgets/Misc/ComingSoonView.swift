import SwiftUI

/// Ported from: lib/core/widgets/coming_soon_view.dart
/// A placeholder empty state for sections or views that are not built or not available yet: an icon tile, a title,
/// a short explanation and an optional action (for example "Switch to List").
public struct ComingSoonView: View {
    @Environment(\.appTheme) private var theme
    let systemImage: String
    let title: String
    let message: String
    let actionLabel: String?
    let onAction: (() -> Void)?

    public init(systemImage: String, title: String, message: String = "", actionLabel: String? = nil, onAction: (() -> Void)? = nil) {
        self.systemImage = systemImage; self.title = title; self.message = message
        self.actionLabel = actionLabel; self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: theme.spacing.s12) {
            Image(systemName: systemImage).font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.control36 * 1.5, height: theme.sizes.control36 * 1.5)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            VStack(spacing: theme.spacing.s4) {
                Text(title).font(theme.typography.title).foregroundStyle(theme.colors.tx)
                if !message.isEmpty { Text(message).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2) }
            }
            .multilineTextAlignment(.center)
            if let actionLabel, let onAction {
                AppButton(actionLabel, kind: .secondary, action: onAction).padding(.top, theme.spacing.s4)
            }
        }
        .frame(maxWidth: theme.sizes.dialogMd)
        .padding(theme.spacing.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
