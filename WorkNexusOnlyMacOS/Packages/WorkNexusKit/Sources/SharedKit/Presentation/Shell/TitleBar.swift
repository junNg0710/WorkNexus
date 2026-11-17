import CoreTools
import CoreUI
import SwiftUI

/// Ported from: app/shell/title_bar — 52pt on macOS; the traffic lights live inside it (hidden-title-bar window).
/// The breadcrumb on the left, a global ticket search (where there is something to search) and the quick-settings gear
/// on the right.
struct TitleBar: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel

    var body: some View {
        @Bindable var model = model
        HStack(spacing: theme.spacing.s12) {
            WorkspaceBreadcrumb(model: model)
            Spacer(minLength: theme.spacing.s12)
            AppGlassContainer(spacing: theme.spacing.s8) {
                HStack(spacing: theme.spacing.s8) {
                    if model.showsGlobalSearch {
                        GlobalSearchField(model: model)
                            .frame(width: theme.sizes.dialogSm - theme.spacing.s40 - theme.spacing.s20, height: theme.sizes.control36)
                            .appGlass(in: Capsule(), fallback: theme.colors.panel2)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                    }
                    AppIconButton("slider.horizontal.3", help: appString("quickSettings", "Quick settings")) { model.quickSettingsOpen.toggle() }
                        .frame(width: theme.sizes.control36, height: theme.sizes.control36)
                        .appGlass(in: Circle(), interactive: true, fallback: theme.colors.panel2)
                        .popover(isPresented: $model.quickSettingsOpen, arrowEdge: .bottom) {
                            model.host.quickSettings().environment(\.appTheme, theme)
                        }
                }
            }
        }
        .animation(.easeOut(duration: theme.motion.base), value: model.showsGlobalSearch)
        .padding(.horizontal, theme.spacing.s8).frame(height: theme.sizes.titleBar - theme.spacing.s8)
        .background(WindowDragArea())
    }
}
