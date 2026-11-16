import CoreDomain
import Foundation

/// The bytes of a chat video fetched in ranges from the server, so a player can start before the download has finished and
/// seek to the index a phone recording keeps at its end. Implemented by Data; the player's loader (Presentation) pulls from it.
/// Ported from: lib/features/chat/data/datasources/chat_video_stream_server.dart (the proxy's role)
public protocol ChatVideoByteSource: Sendable {
    var fileName: String { get }
    /// Size of the whole file in bytes.
    var contentLength: Int64 { get }
    /// Uniform type identifier of the container (`public.mpeg-4`, `com.apple.quicktime-movie`…).
    var contentType: String { get }
    /// Delivers bytes `start...end` (inclusive; nil: to the end of the file) piece by piece through `onChunk` and returns when
    /// they are all out. Cancelling the calling task stops the transfer. A server that ignores `Range` is answered as if it
    /// honoured it (the bytes before `start` are skipped).
    func read(from start: Int64, through end: Int64?, onChunk: @escaping @Sendable (Data) -> Void) async -> Outcome<Void>
}

/// How a video plays.
public enum ChatVideoPlayback: Sendable {
    /// Already on this device.
    case file(URL)
    /// Not (fully) on this device: play while its bytes arrive. Seen whole once, it is kept in the file cache.
    case stream(ChatVideoByteSource)
}
