/// Ported from: lib/features/chat/presentation/widgets/chat_media_strip.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// The chat's photos as a row of small thumbnails along the bottom of the image viewer: the one on show is ringed, a click
/// shows another. Thumbnails load as they scroll into view.
struct ChatImageStrip: View {
    @Environment(\.appTheme) private var theme
    let accountId: String
    let images: [ImageContent]
    let current: ImageContent
    let onPick: (ImageContent) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: theme.spacing.s6) {
                    ForEach(images, id: \.self) { image in
                        StripThumb(accountId: accountId, image: image, selected: image == current) { onPick(image) }.id(image)
                    }
                }
                .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s8)
            }
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, new in withAnimation(.easeOut(duration: theme.motion.base)) { proxy.scrollTo(new, anchor: .center) } }
        }
        .frame(height: theme.sizes.control36 + theme.spacing.s24)
        .background(theme.colors.panel)
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}

private struct StripThumb: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let accountId: String
    let image: ImageContent
    let selected: Bool
    let onTap: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        let side = theme.sizes.control36 + theme.spacing.s8
        Button(action: onTap) {
            ZStack {
                theme.colors.skel2
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
            }
            .frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(selected ? theme.colors.accent : .clear, lineWidth: theme.borders.thick))
            .opacity(selected ? 1 : 0.75)
        }
        .buttonStyle(.plain)
        .task(id: image) {
            guard let repo = services?.chat else { return }
            if let b64 = image.inlineBase64, let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) { thumbnail = NSImage(data: d); return }
            if case .success(let d) = await repo.loadAttachment(accountId: accountId, content: .image(image), thumbnail: true) { thumbnail = NSImage(data: d) }
        }
    }
}
