/// Ported from: lib/features/chat/presentation/widgets/{attachment_download_badge,cancel_download_button,chat_upload_overlay}.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A small round progress ring with a button inside (cancel while transferring).
struct ProgressRing: View {
    @Environment(\.appTheme) private var theme
    let progress: Double?
    var systemImage = "xmark"
    let help: String
    var onTap: (() -> Void)?

    var body: some View {
        Button { onTap?() } label: {
            ZStack {
                Circle().fill(theme.colors.scrim.opacity(0.55))
                if let progress, progress > 0 {
                    Circle().trim(from: 0, to: min(1, progress)).stroke(theme.colors.onScrim, style: StrokeStyle(lineWidth: theme.borders.thick, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(theme.spacing.s2)
                } else {
                    ProgressView().controlSize(.small).tint(theme.colors.onScrim)
                }
                Image(systemName: systemImage).font(.system(size: theme.sizes.icon12, weight: .bold)).foregroundStyle(theme.colors.onScrim)
            }
            .frame(width: theme.sizes.control32, height: theme.sizes.control32)
        }
        .buttonStyle(.plain).help(help)
    }
}

/// On an image that has a server preview: its original size until downloading, then a progress ring with cancel.
struct AttachmentDownloadBadge: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let key: TransferKey
    let size: Int
    @State private var cached = false

    var body: some View {
        let transfers = AttachmentTransfers.shared
        Group {
            if let p = transfers.progress(key) {
                ProgressRing(progress: p, help: appString("chatCancelDownload", "Cancel download")) {
                    if let repo = services?.chat { transfers.cancel(key, repo) }
                }
            } else if !cached {
                Text(AttachmentActions.byteCount(size)).font(theme.typography.caption).foregroundStyle(theme.colors.onScrim)
                    .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s2)
                    .background(theme.colors.scrim.opacity(0.55), in: Capsule())
            }
        }
        .task(id: transfers.isDownloading(key)) {
            if let repo = services?.chat { cached = await transfers.isCached(key, repo) }
        }
    }
}

/// Over an own image or file while it is sent: progress with a cancel button; a failed send offers a retry.
struct ChatUploadOverlay: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let message: ChatMessage
    @State private var progress: Double = 0

    var body: some View {
        Group {
            switch message.sendState {
            case .pending:
                ProgressRing(progress: progress, help: appString("chatCancelUpload", "Cancel sending")) {
                    guard let repo = services?.chat else { return }
                    Task { _ = await repo.cancelUpload(accountId: message.accountId, messageGid: message.gid) }
                }
            case .failed:
                Button {
                    guard let repo = services?.chat else { return }
                    Task { _ = await RetrySendMessage(repo)(accountId: message.accountId, messageGid: message.gid) }
                } label: {
                    Label(appString("chatSendFailed", "Not sent · Retry"), systemImage: "arrow.clockwise")
                        .font(theme.typography.metaStrong).foregroundStyle(theme.colors.onScrim)
                        .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
                        .background(theme.colors.red.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.plain)
            case .sent: EmptyView()
            }
        }
        .task(id: message.sendState == .pending) {
            guard message.sendState == .pending, let repo = services?.chat else { return }
            for await p in repo.watchUploadProgress(messageGid: message.gid) { progress = p }
        }
    }
}
