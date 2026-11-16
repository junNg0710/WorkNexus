/// Ported from: lib/features/chat/presentation/widgets/chat_staged_files.dart
import AppKit
import CoreUI
import ImageIO
import SwiftUI

/// Stands in for the composer's text input while files dropped, pasted or picked wait: their thumbnails, each removable, and the
/// send button. Enter sends, Esc removes them all; no text can be typed meanwhile.
struct StagedFilesStrip: View {
    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool
    let files: [StagedFile]
    let onSend: () -> Void
    let onClear: () -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: theme.spacing.s10) {
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                FlowThumbs(files: files, onRemove: onRemove)
                Text(appString("chatStagedFilesHint", "Enter sends · Esc removes all"))
                    .font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
            }
            Spacer(minLength: 0)
            ComposerSendButton(action: onSend)
        }
        .padding(EdgeInsets(top: theme.spacing.s10, leading: theme.spacing.s24, bottom: theme.spacing.s10, trailing: theme.spacing.s12))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.return) { onSend(); return .handled }
        .onKeyPress(.escape) { onClear(); return .handled }
    }
}

/// The send button (accent disc with a paper plane).
struct ComposerSendButton: View {
    @Environment(\.appTheme) private var theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "paperplane.fill").font(.system(size: theme.sizes.icon16))
                .foregroundStyle(theme.colors.accentTx)
                .frame(width: theme.sizes.control36, height: theme.sizes.control36)
                .background(theme.colors.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .help("\(appString("chatSend", "Send")) · \(appString("chatSendHint", "Enter to send · Shift+Enter for a new line"))")
    }
}

private struct FlowThumbs: View {
    @Environment(\.appTheme) private var theme
    let files: [StagedFile]
    let onRemove: (UUID) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.s10) {
                ForEach(files) { f in StagedThumb(file: f) { onRemove(f.id) } }
            }
        }
    }
}

/// One waiting file: an image's thumbnail, else its type glyph and name, with a remove button in the corner.
private struct StagedThumb: View {
    @Environment(\.appTheme) private var theme
    let file: StagedFile
    let onRemove: () -> Void
    @State private var image: NSImage?
    private var side: CGFloat { theme.sizes.control36 * 2 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: theme.radii.md).fill(theme.colors.panel2)
            if let image {
                Image(nsImage: image).resizable().scaledToFill().frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
            } else {
                VStack(spacing: theme.spacing.s4) {
                    Image(systemName: isVideoName(file.name) ? "film" : "doc").font(.system(size: theme.sizes.icon20)).foregroundStyle(theme.colors.tx2)
                    Text(file.name).font(theme.typography.caption).foregroundStyle(theme.colors.tx2).lineLimit(1).padding(.horizontal, theme.spacing.s4)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: theme.sizes.icon12, weight: .bold)).foregroundStyle(theme.colors.onScrim)
                    .frame(width: theme.sizes.icon20, height: theme.sizes.icon20)
                    .background(theme.colors.scrim.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain).padding(theme.spacing.s4).help(appString("chatRemoveAttachment", "Remove"))
        }
        .frame(width: side, height: side)
        .help(file.name)
        .task(id: file.id) {
            guard ChatStaging.isImageName(file.name) else { return }
            let data = file.data, px = side * 2
            image = await Task.detached { StagedThumb.thumbnail(data, maxPixel: px) }.value
        }
    }

    nonisolated static func thumbnail(_ data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map { NSImage(cgImage: $0, size: .zero) }
    }
}
