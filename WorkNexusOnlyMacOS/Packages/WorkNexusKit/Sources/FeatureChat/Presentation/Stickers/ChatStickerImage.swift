/// Ported from: lib/features/chat/presentation/widgets/chat_sticker_image.dart
import CoreUI
import SwiftUI

/// A sticker's image, loaded through `StickerRepository.bytes` and shown still (grids) or animated.
struct ChatStickerImage: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let sticker: ChatSticker
    var animated = false
    @State private var data: Data?
    @State private var failed = false

    private static let cache = NSCache<NSString, NSData>()

    var body: some View {
        Group {
            if let data { StickerBytesView(data: data, animated: animated) }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(theme.colors.tx3) }
            else { Color.clear }
        }
        .task(id: sticker.id) {
            if let hit = Self.cache.object(forKey: sticker.id as NSString) { data = hit as Data; return }
            guard let repo = services?.stickers else { failed = true; return }
            switch await repo.bytes(sticker) {
            case .success(let d): Self.cache.setObject(d as NSData, forKey: sticker.id as NSString); data = d
            case .failure: failed = true
            }
        }
    }
}
