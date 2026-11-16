import CoreDomain
import CoreUI
import SwiftUI

/// The info panel's "Photos & videos" and "Files" cards: a preview of the newest ones and "See all", which opens the files panel.
/// Ported from: lib/features/chat/presentation/widgets/chat_info_files_section.dart
struct ChatInfoFilesSection: View {
    @Environment(\.chatShellLayout) private var layout
    let model: ChatShellModel
    let session: ChatThreadSession

    private static let previewMedia = 8
    private static let previewFiles = 3

    var body: some View {
        let split = session.attachments.map(ChatShellLabels.splitAttachments)
        let seeAll = { session.state.togglePanel(.files, infoRoom: layout.infoRoom) }
        VStack(spacing: 0) {
            FilesCard(title: split.map { "\(shellString("chatMedia", "Photos & videos")) (\($0.media.count))" } ?? shellString("chatMedia", "Photos & videos"),
                      onSeeAll: (split?.media.isEmpty ?? true) ? nil : seeAll) {
                if let split {
                    if split.media.isEmpty { AppInlineNote(shellString("chatNoMedia", "No photos or videos yet")) }
                    else { ChatMediaGrid(model: model, media: Array(split.media.prefix(Self.previewMedia))) }
                } else { AppInlineSpinner() }
            }
            FilesCard(title: split.map { "\(shellString("chatFiles", "Files")) (\($0.files.count))" } ?? shellString("chatFiles", "Files"),
                      onSeeAll: (split?.files.isEmpty ?? true) ? nil : seeAll) {
                if let split {
                    if split.files.isEmpty { AppInlineNote(shellString("chatNoFiles", "No files yet")) }
                    else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(split.files.prefix(Self.previewFiles)) { m in
                                if let f = m.content.asFile { ChatFileRow(model: model, message: m, file: f) }
                            }
                        }
                    }
                } else { AppInlineSpinner() }
            }
        }
        .task { await session.watchAttachments() }
    }
}

/// One card: a title with an optional "See all" link above its content.
private struct FilesCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let onSeeAll: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        ChatPanelCard {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                HStack {
                    Text(title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                    Spacer(minLength: 0)
                    if let onSeeAll { AppButton(shellString("chatSeeAll", "See all"), kind: .ghost, action: onSeeAll) }
                }
                content
            }
        }
    }
}
