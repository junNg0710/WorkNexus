/// Ported from: lib/features/chat/presentation/widgets/{chat_file_badge,chat_file_action_button}.dart
import CoreUI
import SwiftUI

/// A file's extension on an accent square. While the file moves (`busy`) a translucent ring over it fills with `progress` (spins
/// when unknown); hovering then swaps both for a cross that calls `onCancel`.
struct ChatFileBadge: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let fileName: String
    let busy: Bool
    var progress: Double?
    var onCancel: (() -> Void)?
    var cancelHelp = appString("chatCancelDownload", "Cancel download")

    /// Up to four letters of the extension, upper-cased ("FILE" without one).
    static func label(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "FILE" : String(ext.prefix(4)).uppercased()
    }

    var body: some View {
        let cancellable = busy && onCancel != nil
        let side = theme.sizes.control36 + theme.spacing.s12
        Button { if cancellable { onCancel?() } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radii.md).fill(theme.colors.accent)
                if hovering && cancellable {
                    Image(systemName: "xmark").font(.system(size: theme.sizes.icon20, weight: .semibold)).foregroundStyle(theme.colors.accentTx)
                } else {
                    Text(Self.label(fileName)).font(theme.typography.metaStrong).foregroundStyle(theme.colors.accentTx)
                    if busy {
                        if let progress, progress > 0 {
                            Circle().stroke(theme.colors.accentTx.opacity(0.15), lineWidth: theme.borders.thick + 0.5)
                                .overlay(Circle().trim(from: 0, to: min(1, progress)).stroke(theme.colors.accentTx.opacity(0.6), style: StrokeStyle(lineWidth: theme.borders.thick + 0.5, lineCap: .round)).rotationEffect(.degrees(-90)))
                                .padding(theme.spacing.s6)
                        } else {
                            ProgressView().controlSize(.small).tint(theme.colors.accentTx)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(cancellable ? cancelHelp : fileName)
    }
}

/// A small text action under a file: "Open file", "Show in folder"…
struct ChatFileActionButton: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(theme.typography.metaStrong)
                .foregroundStyle(hovering ? theme.colors.accent : theme.colors.tx2)
                .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
                .background(hovering ? theme.colors.sel : .clear, in: RoundedRectangle(cornerRadius: theme.radii.sm))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}
