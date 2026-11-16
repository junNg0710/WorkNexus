import AppKit
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/detail_header_copy_link_button.dart
/// A header icon button that copies `url` to the clipboard and flips to a check mark (tooltip "Copied!") for
/// `CopyLinkFeedback.duration` seconds as confirmation.
public struct CopyLinkButton: View {
    let url: String; let outlined: Bool
    @State private var copied = false
    @State private var reset: Task<Void, Never>?

    public init(url: String, outlined: Bool = true) { self.url = url; self.outlined = outlined }

    public var body: some View {
        AppIconButton(copied ? "checkmark" : "link", help: copied ? appString("linkCopied", "Copied!") : appString("copyLink", "Copy link"),
                      outlined: outlined) {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string)
            copied = true
            reset?.cancel()
            reset = Task { @MainActor in
                try? await Task.sleep(for: .seconds(CopyLinkFeedback.duration))
                if !Task.isCancelled { copied = false }
            }
        }
        .onDisappear { reset?.cancel() }
    }
}

public enum CopyLinkFeedback {
    /// How long the check mark stays before the link icon returns.
    public static let duration: Double = 1.5
}
