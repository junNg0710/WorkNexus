import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/editor_field.dart
/// A labelled form field; a required one is starred, and `missing` shows it needs filling in - or `missingText`
/// when it is filled in wrongly.
struct EditorField<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let label: String
    var required = false
    var missing = false
    var missingText: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            HStack(spacing: 0) {
                Text(label).foregroundStyle(theme.colors.tx2)
                if required { Text(verbatim: " *").foregroundStyle(theme.colors.red) }
            }
            .font(theme.typography.metaStrong)
            content
            if missing {
                Text(missingText ?? appString("formRequired", "Required")).font(theme.typography.caption).foregroundStyle(theme.colors.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, theme.spacing.s14)
    }
}
