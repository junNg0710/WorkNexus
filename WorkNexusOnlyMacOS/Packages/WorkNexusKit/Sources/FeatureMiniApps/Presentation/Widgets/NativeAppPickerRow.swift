import CoreUI
import SwiftUI

/// New feature, no Dart counterpart. One installed app in the "Add Mac app" list: icon, name, where it is; a check once added.
struct NativeAppPickerRow: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let info: AppBundleInfo
    let model: NativeAppsModel
    let added: Bool
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: theme.spacing.s12) {
                Image(nsImage: model.icon(forPath: info.path)).resizable().interpolation(.high).scaledToFit()
                    .frame(width: theme.sizes.control32, height: theme.sizes.control32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(info.name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                    Text(parent).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1).truncationMode(.head)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if added {
                    Label(appString("nativeAppAdded", "Added"), systemImage: "checkmark")
                        .font(theme.typography.meta).foregroundStyle(theme.colors.green)
                } else if hovering {
                    Image(systemName: "plus.circle").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.accent)
                }
            }
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
            .background(hovering && !added ? theme.colors.panel2 : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.disabled(added)
    }

    /// The folder the app is in, so two copies of one name can be told apart.
    private var parent: String { (info.path as NSString).deletingLastPathComponent }
}
