import CoreDomain
import CoreUI
import SwiftUI

/// Beside the chat: every photo/video (grid) and file (list) shared in it, newest first, from the messages loaded here.
/// Ported from: lib/features/chat/presentation/widgets/chat_files_panel.dart
struct ChatFilesPanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatShellLayout) private var layout
    let model: ChatShellModel
    let session: ChatThreadSession
    @State private var tab = 0

    var body: some View {
        ChatSidePanelFrame(title: shellString("chatFilesAndMedia", "Files & media"),
                           onBack: { session.state.backToInfo(infoRoom: layout.infoRoom) },
                           onClose: { session.state.closePanel() }) {
            if let all = session.attachments {
                let split = ChatShellLabels.splitAttachments(all)
                VStack(spacing: 0) {
                    AppSegmentedTabs([
                        AppSegmentedTab(label: "\(shellString("chatMedia", "Photos & videos")) (\(split.media.count))", active: tab == 0) { tab = 0 },
                        AppSegmentedTab(label: "\(shellString("chatFiles", "Files")) (\(split.files.count))", active: tab == 1) { tab = 1 },
                    ])
                    .padding(.vertical, theme.spacing.s12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: theme.spacing.s8) {
                            if tab == 0 {
                                if split.media.isEmpty { AppInlineNote(shellString("chatNoMedia", "No photos or videos yet")) }
                                else { ChatMediaGrid(model: model, media: split.media, columns: 3) }
                            } else if split.files.isEmpty {
                                AppInlineNote(shellString("chatNoFiles", "No files yet"))
                            } else {
                                ForEach(split.files) { m in if let f = m.content.asFile { ChatFileRow(model: model, message: m, file: f) } }
                            }
                            Text(shellString("chatFilesLoadedHint", "From the messages loaded on this computer; scroll up in the chat to load older ones."))
                                .font(theme.typography.caption).foregroundStyle(theme.colors.tx3).padding(.top, theme.spacing.s12)
                        }
                        .padding(theme.spacing.s12)
                    }
                }
                .background(theme.colors.panel)
            } else {
                AppStateView(.loading)
            }
        }
        .task { await session.watchAttachments() }
    }
}
