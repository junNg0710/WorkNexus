import CoreDomain
import Foundation

/// Ported from: lib/features/panic_switch/data/repositories/asset_panic_sticker_source.dart
/// The sticker from the bundled WorkNexus sticker set (`Stickers/WorkNexus/thay_vo.png`, copied from the Flutter app's
/// `assets/stickers/WorkNexus/thay_vo.png` by `Scripts/sync-assets.sh`: the very bytes the Flutter app sends). Read once.
public final class FilePanicStickerSource: PanicStickerSource, @unchecked Sendable {
    private let url: URL?
    private let lock = NSLock()
    private var cached: Data?

    public init(url: URL?) { self.url = url }

    public func bytes() -> Outcome<Data> {
        lock.lock(); defer { lock.unlock() }
        if let cached { return .success(cached) }
        guard let url, let data = try? Data(contentsOf: url), !data.isEmpty else {
            return .failure(.storage("Could not load the panic sticker"))
        }
        cached = data
        return .success(data)
    }
}
