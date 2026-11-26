import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: app/shell/app_shell.dart, laid out for macOS 26 Liquid Glass: a floating glass sidebar (rail + nav pane)
/// on the left; to its right the title bar and the content as an inset card; the ticket editor covers the card, the
/// notifications panel and the detail slide-over float above, toasts on top.
public struct AppShell: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel

    public init(model: ShellModel) { self.model = model }

    public var body: some View {
        let gap = theme.spacing.s8
        HStack(spacing: gap) {
            SidebarPanel(model: model)
            VStack(spacing: 0) {
                // Folded away with a mini app's bars; the change is animated by whoever folds them (the mini app's tab strip).
                if !model.titleBarHidden { TitleBar(model: model).transition(.move(edge: .top).combined(with: .opacity)) }
                model.host.banner()
                ContentCard {
                    ZStack {
                        Viewport(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let route = model.nav.editor {
                            model.host.editor(route).frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.colors.bg)
                        }
                    }
                }
            }
        }
        .padding(.leading, gap).padding(.trailing, gap).padding(.bottom, gap).padding(.top, gap)
        .onChange(of: model.nav.rail) { _, r in model.noteRail(r) }
        .background(WindowBackdrop())
        .overlay { model.host.overlay(theme.sizes.rail) }
        .detailOverlay(model.detail, railInset: theme.sizes.rail + theme.spacing.s8)
        .overlay { CelebrationOverlay(controller: model.celebration).ignoresSafeArea() }
        .overlay { PetLayer(model: model) }
        .ignoresSafeArea(.container, edges: .top)
        .foregroundStyle(theme.colors.tx)
        .environment(\.celebrate) { model.celebrate() }
        .background(EscapeKeyMonitor { model.handleEscape() })
        .background(RailShortcutMonitor(handle: { model.handleRailShortcut($0) }, held: { model.railHints.modifiersChanged($0) }))
        .toastHost(model.toasts)
        .dialogHost(model.dialogs)
    }
}

/// The window's own surface: a calm panel colour with a soft accent glow top-left, which is what the glass sidebar picks up.
struct WindowBackdrop: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        ZStack {
            theme.colors.panel
            RadialGradient(colors: [theme.colors.accent.opacity(theme.colors.isDark ? 0.22 : 0.14), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 720)
        }
        .ignoresSafeArea()
    }
}

/// Content area: an inset rounded card (the content itself never gets glass).
struct ContentCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous)
        content
            .background(theme.colors.bg, in: shape)
            .clipShape(shape)
            .overlay(shape.stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

/// Rail + nav pane on one floating glass panel (the rail alone when the pane is hidden).
struct SidebarPanel: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    var body: some View {
        HStack(spacing: 0) {
            NavRail(model: model)
            if ToolPaneHost.isVisible(model) {
                Rectangle().fill(theme.colors.line.opacity(0.6)).frame(width: theme.borders.hairline).padding(.vertical, theme.spacing.s12)
            }
            // Always mounted, taking no room while it is not shown (Chat, a mini app, a folded pane): taken out of the
            // tree, every trip to Chat and back built the panes it keeps alive again from nothing.
            ToolPaneHost(model: model)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous))
        .appGlass(in: RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous), fallback: theme.colors.panel2)
    }
}
