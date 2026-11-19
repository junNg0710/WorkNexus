import CoreUI
import SwiftUI

/// Ported from: lib/features/panic_switch/presentation/widgets/panic_steps.dart
/// "How it works" at the top of a tab: a few short steps, each with an icon, filled in with the user's own settings.
struct PanicSteps: View {
    struct Step: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    @Environment(\.appTheme) private var theme
    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s10) {
            Text(appString("panicSwitchHowTitle", "How it works")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
            ForEach(steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s10) {
                    Image(systemName: step.icon).font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.accent)
                        .frame(width: theme.sizes.icon16)
                    Text(step.text).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(theme.spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .padding(.horizontal, theme.spacing.s20).padding(.bottom, theme.spacing.s20)
    }
}
