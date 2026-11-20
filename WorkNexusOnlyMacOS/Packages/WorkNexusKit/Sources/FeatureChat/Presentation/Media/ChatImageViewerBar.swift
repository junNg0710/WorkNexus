/// Ported from: lib/features/chat/presentation/widgets/chat_image_viewer_bar.dart
import CoreUI
import SwiftUI

/// What the bar above a picture offers.
struct ChatImageViewerActions {
    var onZoom: (CGFloat) -> Void
    var onFit: () -> Void
    var onRotate: () -> Void
    var onSaveAs: () -> Void
    var onCopy: () -> Void
    var onSticker: (() -> Void)?
    var onOpen: () -> Void
    var onClose: () -> Void
    /// Zoom, rotate, copy and save as sticker apply to a picture; a video has its own controls.
    var pictureTools = true
}

/// The picture's name and facts (place among the chat's pictures, size in pixels, file size) on the left; zoom, rotate,
/// save and copy on the right, the rarer actions under "…". A short confirmation ("Copied") shows beside the name.
struct ChatImageViewerBar: View {
    @Environment(\.appTheme) private var theme
    let name: String
    let facts: String
    let note: String?
    let zoom: CGFloat
    let actions: ChatImageViewerActions

    var body: some View {
        HStack(spacing: theme.spacing.s4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1).truncationMode(.middle)
                HStack(spacing: theme.spacing.s8) {
                    if !facts.isEmpty { Text(facts).font(theme.typography.caption).foregroundStyle(theme.colors.tx3).lineLimit(1) }
                    if let note { Text(note).font(theme.typography.caption).foregroundStyle(theme.colors.accent).lineLimit(1).transition(.opacity) }
                }
            }
            .layoutPriority(1)
            Spacer(minLength: theme.spacing.s12)
            if actions.pictureTools {
                AppIconButton("minus.magnifyingglass", help: appString("chatZoomOut", "Zoom out")) { actions.onZoom(1 / 1.25) }
                Button(action: actions.onFit) {
                    Text(verbatim: "\(Int((zoom * 100).rounded()))%").font(theme.typography.metaStrong).monospacedDigit().foregroundStyle(theme.colors.tx2)
                        .frame(minWidth: 44)
                }
                .buttonStyle(.plain).help(appString("chatZoomFit", "Fit to screen"))
                AppIconButton("plus.magnifyingglass", help: appString("chatZoomIn", "Zoom in")) { actions.onZoom(1.25) }
                AppIconButton("rotate.right", help: appString("chatRotate", "Rotate"), action: actions.onRotate)
                Divider().frame(height: theme.sizes.icon20).padding(.horizontal, theme.spacing.s4)
            }
            AppIconButton("square.and.arrow.down", help: appString("chatSaveAs", "Save as…"), action: actions.onSaveAs)
            if actions.pictureTools { AppIconButton("doc.on.doc", help: appString("chatCopyImage", "Copy image"), action: actions.onCopy) }
            ViewerMoreMenu(actions: actions)
            ViewerSizeButtons()
            AppIconButton("xmark", help: appString("chatClosePanel", "Close"), action: actions.onClose)
        }
        .padding(.horizontal, theme.spacing.s16)
        .frame(height: theme.sizes.titleBar)
        .background(theme.colors.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        .animation(.easeOut(duration: theme.motion.fast), value: note)
    }
}

/// "…": save as sticker, open in the default app.
private struct ViewerMoreMenu: View {
    @Environment(\.appTheme) private var theme
    let actions: ChatImageViewerActions

    var body: some View {
        AppMenuButton(help: appString("more", "More"), items: {
            var out: [AppNativeMenu.Item] = []
            if actions.pictureTools, let onSticker = actions.onSticker {
                out.append(.init(appString("chatSaveSticker", "Save as sticker"), icon: "face.smiling", action: onSticker))
            }
            out.append(.init(appString("chatOpenWith", "Open in default app"), icon: "arrow.up.forward.app", action: actions.onOpen))
            return out
        }) {
            Image(systemName: "ellipsis").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.control32, height: theme.sizes.control32).contentShape(Rectangle())
        }
        .fixedSize()
    }
}

/// The large previous / next buttons at the picture's sides, shown while the pointer is over it.
struct ChatImageStageArrow: View {
    @Environment(\.appTheme) private var theme
    let next: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: next ? "chevron.right" : "chevron.left").font(.system(size: theme.sizes.icon20, weight: .semibold))
                .foregroundStyle(theme.colors.onScrim)
                .frame(width: 44, height: 44)
                .background(theme.colors.scrim.opacity(0.45), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(next ? appString("chatNext", "Next") : appString("chatPrevious", "Previous"))
        .padding(.horizontal, theme.spacing.s16)
    }
}
