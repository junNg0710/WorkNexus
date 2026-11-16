/// Ported from: lib/features/chat/presentation/widgets/chat_storage_meter.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The cache at a glance: how much is used (large) against the limit, a bar for the limit split by kind — photos, videos,
/// files, other — and their legend. The figure turns to the warning colour near the limit.
struct ChatStorageMeter: View {
    @Environment(\.appTheme) private var theme
    let usage: ChatCacheUsage
    let limitBytes: Int

    var body: some View {
        let used = usage.totalBytes
        let ratio = limitBytes <= 0 ? 0 : min(max(Double(used) / Double(limitBytes), 0), 1)
        let near = ratio > 0.9
        let kinds = ChatStorageLogic.kinds(imageBytes: usage.chats.reduce(0) { $0 + $1.imageBytes },
                                           videoBytes: usage.chats.reduce(0) { $0 + $1.videoBytes },
                                           fileBytes: usage.chats.reduce(0) { $0 + $1.fileBytes }, theme: theme)
            + [ChatStorageKind(label: shellString("chatStorageOther", "Other files"), bytes: usage.otherBytes, color: theme.colors.tx3)]
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s6) {
                Text(ChatShellLabels.fileSize(used)).font(theme.typography.title).foregroundStyle(near ? theme.colors.amber : theme.colors.tx)
                Text("/ \(ChatShellLabels.fileSize(limitBytes))").font(theme.typography.body).foregroundStyle(theme.colors.tx2)
                Spacer(minLength: 0)
                Text(ChatStorageLogic.percent(ratio)).font(theme.typography.bodyStrong).foregroundStyle(near ? theme.colors.amber : theme.colors.tx2)
            }
            ChatStorageBar(total: limitBytes, parts: kinds.map { ($0.bytes, $0.color) }, height: theme.spacing.s12)
            if used > 0 { ChatStorageLegend(kinds: kinds) }
        }
        .padding(theme.spacing.s16).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}
