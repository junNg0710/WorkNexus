import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/core/widgets/app_state_view.dart (loading / error with retry, as the editor uses them)
struct EditorLoadState: View {
    @Environment(\.appTheme) private var theme
    let failure: Failure?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: theme.spacing.s10) {
            if let failure {
                Image(systemName: "exclamationmark.triangle").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.red)
                Text(appString("formLoadFailed", "Couldn't load the form")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                Text(failure.message).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).multilineTextAlignment(.center)
                AppButton(appString("retry", "Retry"), action: onRetry)
            } else {
                ProgressView().controlSize(.regular)
            }
        }
        .padding(theme.spacing.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
