/// Ported from: lib/features/chat/presentation/widgets/chat_avatar_crop_dialog.dart
import AppKit
import CoreDomain
import CoreUI
import ImageIO
import SwiftUI

/// Lets the user pick the square of an image that becomes their avatar; `onApply` gets that square (in the picture's own
/// pixels), `onCancel` runs when dismissed.
struct ChatAvatarCropDialog: View {
    @Environment(\.appTheme) private var theme
    let imageData: Data
    let onApply: (ChatAvatarCrop?) -> Void
    let onCancel: () -> Void
    @State private var crop: ChatAvatarCrop?

    /// At most this share of the dialog goes to the picture, so a tall one still leaves room for the title and buttons.
    private static let pictureHeight: CGFloat = 0.6

    /// The picture's size in pixels; nil when it cannot be decoded.
    static func pixelSize(_ data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    var body: some View {
        let size = Self.pixelSize(imageData)
        let image = NSImage(data: imageData)
        AppDialogFrame(title: shellString("chatCropAvatarTitle", "Crop your picture"), maxWidth: theme.sizes.dialogLg, onClose: onCancel) {
            VStack(spacing: theme.spacing.s8) {
                if let size, let image {
                    ChatAvatarCropView(image: image, imageSize: size,
                                       maxSize: CGSize(width: theme.sizes.dialogLg - theme.spacing.s24 * 2, height: theme.sizes.dialogLg * Self.pictureHeight),
                                       onChange: { crop = $0 })
                    Text(shellString("chatCropAvatarHint", "Drag the frame to move it; drag a corner to resize it"))
                        .font(theme.typography.meta).foregroundStyle(theme.colors.tx3).multilineTextAlignment(.center)
                } else {
                    AppInlineNote(shellString("chatCropAvatarUnreadable", "This picture can't be opened"), isError: true)
                }
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24).frame(maxWidth: .infinity)
        } actions: {
            Spacer(minLength: 0)
            AppButton(shellString("chatCancel", "Cancel"), kind: .ghost, action: onCancel)
            AppButton(shellString("chatCropAvatarApply", "Use this picture"), kind: .primary) { onApply(crop) }.disabled(size == nil || image == nil)
        }
    }
}
