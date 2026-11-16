import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// Images and videos of a chat as a grid of square thumbnails; a tap opens the file.
/// Ported from: lib/features/chat/presentation/widgets/chat_shared_files.dart
struct ChatMediaGrid: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let media: [ChatMessage]
    var columns = 4

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.s4), count: columns), spacing: theme.spacing.s4) {
            ForEach(media) { MediaThumb(model: model, message: $0) }
        }
    }
}

/// One square thumbnail: the image's preview or a video's first frame, loaded on demand.
/// Ported from: lib/features/chat/presentation/widgets/chat_media_grid_thumb.dart
private struct MediaThumb: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let message: ChatMessage
    @State private var image: NSImage?

    var body: some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    theme.colors.panel2
                    if let image { Image(nsImage: image).resizable().scaledToFill() }
                    if isVideo { Image(systemName: "play.circle.fill").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.onScrim) }
                    if model.downloading.contains(message.content) { ProgressView().controlSize(.small) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
            .contentShape(Rectangle())
            .onTapGesture { Task { await model.open(attachment: message.content) } }
            .task(id: message.gid) { await load() }
    }

    private var isVideo: Bool { chatMediaKind(of: message.content) == .video }

    private func load() async {
        let result = isVideo
            ? await LoadVideoThumbnail(model.repository)(accountId: model.accountId, video: message.content)
            : await LoadChatAttachment(model.repository)(accountId: model.accountId, content: message.content, thumbnail: true)
        if case .success(let data) = result { image = NSImage(data: data) }
    }
}

/// One shared file: extension badge, name, size and date; a tap downloads (when needed) and opens it.
/// Ported from: lib/features/chat/presentation/widgets/chat_shared_files.dart
struct ChatFileRow: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let message: ChatMessage
    let file: FileContent

    var body: some View {
        let downloading = model.downloading.contains(message.content)
        HoverSurface(onTap: { Task { await model.open(attachment: message.content) } }, enabled: !downloading) {
            HStack(spacing: theme.spacing.s12) {
                ZStack {
                    theme.colors.accent
                    if downloading { ProgressView().controlSize(.small).tint(theme.colors.accentTx) }
                    else { Text(ChatShellLabels.fileBadge(file.name)).font(theme.typography.label).foregroundStyle(theme.colors.accentTx) }
                }
                .frame(width: theme.sizes.control36 + theme.spacing.s4, height: theme.sizes.control36 + theme.spacing.s4)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
                VStack(alignment: .leading, spacing: theme.spacing.s2) {
                    Text(file.name).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1)
                    Text("\(ChatShellLabels.fileSize(file.size)) · \(message.sentAt.formatted(date: .numeric, time: .omitted))")
                        .font(theme.typography.caption).foregroundStyle(theme.colors.tx2)
                }
                Spacer(minLength: 0)
                AppIconButton("arrow.down.circle", help: shellString("chatSaveAs", "Save as…")) {
                    Task { await model.save(attachment: message.content, name: file.name) }
                }
            }
            .padding(.vertical, theme.spacing.s6)
        }
    }
}
