/// Ported from: lib/features/chat/data/datasources/chat_video_stream_server.dart (the player-facing half of the proxy)
import AVFoundation
import CoreDomain
import Foundation

/// Serves an `AVURLAsset` from a `ChatVideoByteSource`: every byte-range request AVFoundation makes (the first bytes, the
/// index a phone recording keeps at its end, a seek) becomes one ranged transfer from the server, so playback starts before
/// the download has finished. Create the asset on `assetURL(for:)` and keep this object alive as long as the asset.
final class ChatVideoSourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "wnchatvideo"

    private final class Pending: @unchecked Sendable {
        let request: AVAssetResourceLoadingRequest
        var task: Task<Void, Never>?
        init(_ r: AVAssetResourceLoadingRequest) { request = r }
    }

    let source: ChatVideoByteSource
    let queue = DispatchQueue(label: "worknexus.chat.video-loader")
    private let lock = NSLock()
    private var pending: [ObjectIdentifier: Pending] = [:]

    init(source: ChatVideoByteSource) { self.source = source }

    deinit { cancelAll() }

    /// A URL no one else can open, ending in the file name (some players pick the format from it).
    static func assetURL(for source: ChatVideoByteSource) -> URL {
        var c = URLComponents()
        c.scheme = scheme; c.host = "video"
        c.path = "/" + (source.fileName.isEmpty ? "video" : source.fileName)
        return c.url ?? URL(string: "\(scheme)://video/video")!
    }

    /// An asset that streams from the source; the loader is retained by the returned pair.
    static func asset(for source: ChatVideoByteSource) -> (asset: AVURLAsset, loader: ChatVideoSourceLoader) {
        let loader = ChatVideoSourceLoader(source: source)
        let asset = AVURLAsset(url: assetURL(for: source))
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return (asset, loader)
    }

    func cancelAll() {
        lock.lock(); let all = pending.values; pending = [:]; lock.unlock()
        all.forEach { $0.task?.cancel() }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard loadingRequest.request.url?.scheme == Self.scheme else { return false }
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = source.contentType
            info.contentLength = source.contentLength
            info.isByteRangeAccessSupported = true
        }
        guard let data = loadingRequest.dataRequest else { loadingRequest.finishLoading(); return true }
        let start = data.currentOffset
        let end: Int64? = data.requestsAllDataToEndOfResource ? nil : data.requestedOffset + Int64(data.requestedLength) - 1
        let entry = Pending(loadingRequest)
        let key = ObjectIdentifier(loadingRequest)
        lock.lock(); pending[key] = entry; lock.unlock()
        let source = source
        entry.task = Task { [weak self] in
            let result = await source.read(from: start, through: end) { chunk in data.respond(with: chunk) }
            self?.lock.lock(); self?.pending[key] = nil; self?.lock.unlock()
            switch result {
            case .success: loadingRequest.finishLoading()
            case .failure(let f):
                if case .cancelled = f { return }
                loadingRequest.finishLoading(with: NSError(domain: "WorkNexus.ChatVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: f.message]))
            }
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        lock.lock(); let entry = pending.removeValue(forKey: ObjectIdentifier(loadingRequest)); lock.unlock()
        entry?.task?.cancel()
    }
}
