/// Ported from: lib/features/chat/presentation/widgets/chat_media_strip.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// The chat's pictures and videos as a row of small thumbnails along the bottom of the media viewer: the one on show is
/// ringed, a click shows another; a video carries a play mark. Thumbnails load as they scroll into view.
struct ChatImageStrip: View {
    @Environment(\.appTheme) private var theme
    let accountId: String
    let items: [ChatMediaItem]
    let current: ChatMediaItem
    let onPick: (ChatMediaItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: theme.spacing.s6) {
                    ForEach(items, id: \.self) { item in
                        StripThumb(accountId: accountId, item: item, selected: item == current) { onPick(item) }.id(item)
                    }
                }
                .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s8)
            }
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, new in withAnimation(.easeOut(duration: theme.motion.base)) { proxy.scrollTo(new, anchor: .center) } }
        }
        .frame(height: StripThumb.side + theme.spacing.s20)
        // Part of the dark stage, so the picture and its neighbours read as one surface.
        .background(theme.colors.scrim.opacity(0.85))
    }
}

private struct StripThumb: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let accountId: String
    let item: ChatMediaItem
    let selected: Bool
    let onTap: () -> Void
    @State private var thumbnail: NSImage?
    static let side: CGFloat = 60

    var body: some View {
        let side = Self.side
        Button(action: onTap) {
            ZStack {
                theme.colors.skel2
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
                if case .video = item {
                    Image(systemName: "play.fill").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.onScrim)
                        .padding(theme.spacing.s6).background(theme.colors.scrim.opacity(0.55), in: Circle())
                }
            }
            .frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(selected ? theme.colors.onScrim : .clear, lineWidth: theme.borders.thick))
            .opacity(selected ? 1 : 0.55)
            .scaleEffect(selected ? 1 : 0.92)
            .animation(.easeOut(duration: theme.motion.fast), value: selected)
        }
        .buttonStyle(.plain)
        .task(id: item) {
            guard let repo = services?.chat else { return }
            switch item {
            case .image(let image):
                if let b64 = image.inlineBase64, let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) { thumbnail = NSImage(data: d); return }
                if case .success(let d) = await repo.loadAttachment(accountId: accountId, content: .image(image), thumbnail: true) { thumbnail = NSImage(data: d) }
            case .video(let file):
                if case .success(let d) = await repo.videoThumbnail(accountId: accountId, video: .file(file)) { thumbnail = NSImage(data: d) }
            }
        }
    }
}
