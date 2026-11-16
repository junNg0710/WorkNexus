import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_load_error.dart
/// Covers the page when it could not load: what went wrong and a way to try again.
struct MiniAppLoadErrorView: View {
    @Environment(\.appTheme) private var theme
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: theme.spacing.s12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx3)
            Text(appString("miniAppLoadFailed", "This page couldn't be loaded")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
            Text(message).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).multilineTextAlignment(.center).lineLimit(4)
            AppButton(appString("miniAppRetry", "Try again"), kind: .primary, action: onRetry)
        }
        .padding(theme.spacing.s24).frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.colors.bg)
    }
}
