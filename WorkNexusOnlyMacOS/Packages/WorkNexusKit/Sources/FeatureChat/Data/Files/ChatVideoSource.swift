import CoreDomain
import Foundation
import UniformTypeIdentifiers

/// A chat video read from the server in byte ranges (`XxdRangeStream` with the pinned certificate). The first pass that runs
/// from the first byte to the last is also written to a temporary file, which `onComplete` then moves into the file cache — a
/// video played once is on this device afterwards, like one downloaded.
/// Ported from: lib/features/chat/data/datasources/chat_video_stream_server.dart (upstream route)
final class UpstreamVideoSource: ChatVideoByteSource, @unchecked Sendable {
    let fileName: String
    let contentLength: Int64
    let contentType: String
    private let url: URL
    private let pin: String?
    private let onComplete: (@Sendable (URL) -> Void)?
    private let recording = Locked(false)

    init(url: URL, pin: String?, fileName: String, length: Int64, mimeType: String?, onComplete: (@Sendable (URL) -> Void)?) {
        self.url = url; self.pin = pin; self.fileName = fileName; contentLength = length; self.onComplete = onComplete
        contentType = Self.uti(fileName: fileName, mimeType: mimeType)
    }

    /// The container's UTI from its mime type or extension; the generic movie type when neither says.
    static func uti(fileName: String, mimeType: String?) -> String {
        if let mimeType, let t = UTType(mimeType: mimeType), t.conforms(to: .audiovisualContent) { return t.identifier }
        let ext = (fileName as NSString).pathExtension
        if !ext.isEmpty, let t = UTType(filenameExtension: ext), t.conforms(to: .audiovisualContent) { return t.identifier }
        return UTType.movie.identifier
    }

    func read(from start: Int64, through end: Int64?, onChunk: @escaping @Sendable (Data) -> Void) async -> Outcome<Void> {
        let whole = start == 0 && (end.map { $0 >= contentLength - 1 } ?? true)
        let recorder = whole && onComplete != nil && recording.with({ r in if r { return false }; r = true; return true }) ? Recorder() : nil
        let result = await XxdRangeStream.run(url, pinnedFingerprint: pin, start: start, end: end) { data in
            recorder?.append(data)
            onChunk(data)
        }
        if let recorder {
            recording.with { $0 = false }
            if case .success = result, recorder.count == contentLength, let file = recorder.finish() { onComplete?(file) } else { recorder.discard() }
        }
        return result
    }

    /// The temporary file a whole pass is copied into.
    private final class Recorder: @unchecked Sendable {
        private let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-video-\(UUID().uuidString)")
        private var handle: FileHandle?
        private(set) var count: Int64 = 0
        private let lock = NSLock()

        func append(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            if handle == nil {
                FileManager.default.createFile(atPath: url.path, contents: nil)
                handle = try? FileHandle(forWritingTo: url)
            }
            try? handle?.write(contentsOf: data)
            count += Int64(data.count)
        }

        func finish() -> URL? { lock.lock(); defer { lock.unlock() }; try? handle?.close(); handle = nil; return count > 0 ? url : nil }
        func discard() { lock.lock(); try? handle?.close(); handle = nil; lock.unlock(); try? FileManager.default.removeItem(at: url) }
    }
}
