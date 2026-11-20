import AppKit
import ImageIO
import SwiftUI

/// Ported from: lib/core/widgets/inline_image.dart
/// An inline image in a description or comment (Markdown or HTML), fetched through `loader` (once per URL),
/// with loading / broken states. A click opens it enlarged in `ImageViewerDialog` and the context menu offers to
/// copy it, unless `zoomable` is off. When the bytes could not be fetched but `fallbackUrl` resolves, a "copy link /
/// open in browser" bar is shown instead of the broken-image icon.
public struct InlineImage: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.imageViewerPresenter) private var presenter
    @Environment(\.toasts) private var toasts
    private enum Phase { case loading, loaded(Data, NSImage), failed }
    @State private var phase: Phase = .loading
    @State private var viewer: ImageViewerRequest?

    let url: String; let loader: ImageBytesLoader
    let fallbackUrl: ImageUrlResolver?; let onOpenImage: ImageExternalOpener?
    let width: CGFloat?; let zoomable: Bool

    public init(url: String, loader: @escaping ImageBytesLoader, fallbackUrl: ImageUrlResolver? = nil,
                onOpenImage: ImageExternalOpener? = nil, width: CGFloat? = nil, zoomable: Bool = true) {
        self.url = url; self.loader = loader; self.fallbackUrl = fallbackUrl; self.onOpenImage = onOpenImage
        self.width = width; self.zoomable = zoomable
    }

    public var body: some View {
        Group {
            switch phase {
            case .loading: ImageFrame { ProgressView().controlSize(.small) }
            case .failed:
                if let resolved = fallbackUrl?(url) { ImageFrame { ImageFallbackActions(url: resolved, onOpen: onOpenImage) } }
                else { ImageFrame { Image(systemName: "photo").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx3) } }
            case .loaded(let data, let image):
                LoadedInlineImage(data: data, image: image, width: width, zoomable: zoomable, externalUrl: fallbackUrl?(url),
                                  onOpenImage: onOpenImage) { req in
                    if let presenter { presenter(req) } else { viewer = req }
                }
            }
        }
        .task(id: url) {
            phase = .loading
            if let data = await loader(url), let img = decodeInlineImage(data) { phase = .loaded(data, img) } else { phase = .failed }
        }
        .sheet(item: $viewer) { req in
            ImageViewerDialog(data: req.data, externalUrl: req.externalUrl, onOpenExternally: req.onOpenExternally) { viewer = nil }
        }
    }
}

/// The picture in `data`: AppKit's own reading, else the first frame ImageIO can decode (some formats AppKit turns down
/// still read there), so bytes that were fetched are not shown as a broken image.
func decodeInlineImage(_ data: Data) -> NSImage? {
    if let image = NSImage(data: data), image.isValid { return image }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
          let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
}

/// The loading / broken placeholder box of an inline image.
private struct ImageFrame<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content.frame(maxWidth: .infinity).frame(height: 140)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .padding(.vertical, theme.spacing.s6)
    }
}

/// A fetched inline image: click to enlarge, context menu to copy / open.
private struct LoadedInlineImage: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let data: Data; let image: NSImage; let width: CGFloat?; let zoomable: Bool
    let externalUrl: String?; let onOpenImage: ImageExternalOpener?
    let present: (ImageViewerRequest) -> Void

    var body: some View {
        Image(nsImage: image).resizable().scaledToFit()
            // A chosen width is honoured as is; otherwise tall images are capped.
            .frame(width: width, alignment: .leading).frame(maxHeight: width == nil ? 400 : nil)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
            .padding(.vertical, theme.spacing.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .pointerStyle(zoomable ? .zoomIn : .default)
            .onTapGesture {
                guard zoomable else { return }
                present(ImageViewerRequest(data: data, externalUrl: externalUrl, onOpenExternally: onOpenImage))
            }
            .contextMenu {
                if zoomable {
                    Button(appString("copyImage", "Copy image")) {
                        copyImageToClipboard(data)
                        toasts?.show(appString("imageCopied", "Copied"))
                    }
                    if let externalUrl, let open = onOpenImage {
                        Button(appString("openImageInBrowser", "Open image in browser")) { Task { await open(externalUrl) } }
                    }
                }
            }
    }
}

/// The action bar shown in place of an inline image whose bytes couldn't be fetched: copy the resolved link, or
/// open it in a browser. Copy shows a transient "copied" state.
struct ImageFallbackActions: View {
    @Environment(\.appTheme) private var theme
    @State private var copied = false
    let url: String; let onOpen: ImageExternalOpener?
    var body: some View {
        HStack(spacing: 0) {
            FallbackChip(symbol: copied ? "checkmark" : "link", label: copied ? appString("linkCopied", "Copied!") : appString("copyLink", "Copy link")) {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            }
            if let onOpen {
                Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline, height: theme.sizes.icon16)
                FallbackChip(symbol: "arrow.up.right.square", label: appString("openImageInBrowser", "Open image in browser")) { Task { await onOpen(url) } }
            }
        }
    }
}

private struct FallbackChip: View {
    @Environment(\.appTheme) private var theme
    let symbol: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: symbol).font(.system(size: theme.sizes.icon14))
                Text(label).font(theme.typography.paragraph).lineLimit(1)
            }
            .foregroundStyle(theme.colors.accent)
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
