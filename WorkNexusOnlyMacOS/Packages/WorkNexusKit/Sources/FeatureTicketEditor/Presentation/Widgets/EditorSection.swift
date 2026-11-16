import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/editor_section.dart
/// A group of editor fields in the app's panel-card style: a surface with a hairline border under an icon and title.
struct EditorSection<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s14) {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: systemImage).font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx2)
                Text(title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                Spacer(minLength: 0)
            }
            content
        }
        .padding(.horizontal, theme.spacing.s20).padding(.top, theme.spacing.s14).padding(.bottom, theme.spacing.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.panel, in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}
