import AppKit
import SwiftUI

/// Ported from: lib/core/widgets/image_viewer_dialog.dart
/// An image from a description or comment, enlarged: zoom with the wheel or a pinch, drag to pan, double-click to
/// zoom in about the pointer or back to fit (`ZoomableImage`). The bar's copy button or the context menu copies it.
/// Esc, the close button or a click beside the image closes it. `onClose` is called to dismiss (the caller owns the
/// sheet / overlay).
public struct ImageViewerDialog: View {
    @Environment(\.appTheme) private var theme
    @State private var copied = false
    let data: Data; let externalUrl: String?; let onOpenExternally: ImageExternalOpener?; let onClose: () -> Void

    public init(data: Data, externalUrl: String? = nil, onOpenExternally: ImageExternalOpener? = nil, onClose: @escaping () -> Void) {
        self.data = data; self.externalUrl = externalUrl; self.onOpenExternally = onOpenExternally; self.onClose = onClose
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle().fill(theme.colors.scrim.opacity(0.85)).contentShape(Rectangle()).onTapGesture(perform: onClose)
            if let image = NSImage(data: data) {
                ZoomableImage(image: image, minScale: 0.5, maxScale: 8, inset: theme.spacing.s40, onBackgroundTap: onClose)
                    .contextMenu {
                        Button(appString("copyImage", "Copy image")) { copy() }
                        if let url = externalUrl, let open = onOpenExternally {
                            Button(appString("openImageInBrowser", "Open image in browser")) { Task { await open(url) } }
                        }
                    }
            }
            HStack(spacing: theme.spacing.s4) {
                AppIconButton(copied ? "checkmark" : "doc.on.doc", help: copied ? appString("imageCopied", "Copied") : appString("copyImage", "Copy image"), action: copy)
                if let url = externalUrl, let open = onOpenExternally {
                    AppIconButton("arrow.up.right.square", help: appString("openImageInBrowser", "Open image in browser")) { Task { await open(url) } }
                }
                AppIconButton("xmark", help: appString("close", "Close"), action: onClose)
            }
            .padding(theme.spacing.s4).background(theme.colors.card, in: Capsule()).padding(theme.spacing.s20)
        }
        .onExitCommand(perform: onClose)
    }

    private func copy() {
        copyImageToClipboard(data)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}
