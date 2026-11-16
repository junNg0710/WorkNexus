import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_icon_picker.dart
/// The icon field of the edit dialog: a preview and the ways to change it — pick an image or take the site's own icon.
struct MiniAppIconPicker: View {
    @Environment(\.appTheme) private var theme
    let name: String
    let iconPath: String?
    /// An icon is being fetched or copied in.
    let busy: Bool
    let onChoose: () -> Void
    let onUseSite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            Text(appString("miniAppIcon", "Icon")).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
            HStack(spacing: theme.spacing.s14) {
                Group {
                    if busy { ProgressView().controlSize(.small) }
                    else { MiniAppIconView(app: MiniApp(id: "", name: name, url: "", iconPath: iconPath, position: 0), size: theme.sizes.icon24 + theme.sizes.icon14) }
                }
                .frame(width: 48, height: 48)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.lg))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                VStack(alignment: .leading, spacing: theme.spacing.s8) {
                    AppButton(appString("miniAppIconChoose", "Choose image…"), systemImage: "photo", action: onChoose).disabled(busy)
                    AppButton(appString("miniAppIconSite", "Use site icon"), systemImage: "globe", action: onUseSite).disabled(busy)
                }
            }
        }
    }
}
