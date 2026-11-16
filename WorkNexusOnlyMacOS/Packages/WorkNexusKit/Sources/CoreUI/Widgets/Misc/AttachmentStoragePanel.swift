import CoreDomain
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/attachment_storage_panel.dart
/// Disk taken by ticket attachments - videos kept by the stream cache and files opened this session - with a button to
/// clear it. The ticket part of the app's storage settings; provider-agnostic: the host passes the two closures
/// (`SyncCoordinator.attachmentStorageBytes` / `clearAttachmentStorage` in the app).
public struct AttachmentStoragePanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let usage: () async -> Outcome<Int>
    let clear: () async -> Outcome<Void>
    @State private var bytes: Outcome<Int>?
    @State private var clearing = false
    @State private var confirming = false

    public init(usage: @escaping () async -> Outcome<Int>, clear: @escaping () async -> Outcome<Void>) {
        self.usage = usage; self.clear = clear
    }

    private var isEmpty: Bool { if case .success(0)? = bytes { true } else { false } }

    private func doClear() {
        clearing = true
        Task {
            let result = await clear()
            bytes = await usage()
            clearing = false
            let ok = (try? result.get()) != nil
            toasts?.show(ok ? appString("chatStorageCleared", "Cleared")
                         : appString("attachmentStorageFailed", "Couldn't read or clear the attachment storage"), kind: ok ? .success : .error)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s14) {
            Text(appString("attachmentStorageHint", "Videos played from tickets are kept so they open instantly next time; files opened this session sit alongside them."))
                .font(theme.typography.caption).foregroundStyle(theme.colors.tx2)
            switch bytes {
            case .success(let n)?:
                Text(appFormat("attachmentStorageUsed", "Using %1$@", formatFileSize(n) ?? "0 B"))
                    .font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
            case .failure?: AppInlineNote(appString("attachmentStorageFailed", "Couldn't read or clear the attachment storage"), isError: true)
            case nil: AppInlineSpinner()
            }
            HStack(spacing: theme.spacing.s8) {
                AppButton(appString("attachmentStorageClear", "Clear"), kind: .danger) { confirming = true }
                    .disabled(isEmpty || clearing)
                if clearing { ProgressView().controlSize(.small) }
            }
        }
        .task { bytes = await usage() }
        .appConfirmDialog(isPresented: $confirming, title: appString("chatStorageClearTitle", "Delete downloaded files?"),
                          message: appString("attachmentStorageClearConfirm", "Delete the downloaded ticket videos and attachments? They download again when opened."),
                          confirmLabel: appString("attachmentStorageClear", "Clear"), destructive: true, onConfirm: doClear)
    }
}
