import CoreDomain
import Foundation

/// One ranged GET through the pinning policy that hands the body out piece by piece (no buffering): the transfer a video
/// player's byte-range request becomes. A server that answers `200` with the whole file instead of `206` is read as if it
/// honoured the range — the bytes before `start` are skipped and the transfer stops once `end` is out.
/// Ported from: lib/features/chat/data/datasources/chat_video_stream_server.dart (`_serve`, `sliceStream`)
final class XxdRangeStream: XxdPinningDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var skip: Int64 = 0
        var position: Int64 = 0
        var finishedEarly = false
        var failure: Failure?
        var head: HTTPURLResponse?
        var continuation: CheckedContinuation<Outcome<Void>, Never>?
    }

    private let state = Locked(State())
    #if DEBUG
    /// DEBUG: told each transfer's range and the server's answer (`ChatVideoProbe`).
    nonisolated(unsafe) static var trace: (@Sendable (String) -> Void)?
    /// DEBUG: bytes handed on by every transfer since the app started.
    static let delivered = Locked(Int64(0))
    #endif
    private var start: Int64 = 0
    private var end: Int64?
    private var onChunk: (@Sendable (Data) -> Void)?

    /// Streams bytes `start...end` (nil: to the end) of `url` through `onChunk`.
    static func run(_ url: URL, pinnedFingerprint: String?, start: Int64, end: Int64?,
                    onChunk: @escaping @Sendable (Data) -> Void) async -> Outcome<Void> {
        let policy = XxdTLSPolicy(pinnedFingerprint: pinnedFingerprint)
        let stream = XxdRangeStream(policy: policy)
        stream.start = start; stream.end = end; stream.onChunk = onChunk
        var request = URLRequest(url: url, timeoutInterval: 60)
        if start > 0 || end != nil { request.setValue("bytes=\(start)-\(end.map(String.init) ?? "")", forHTTPHeaderField: "Range") }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false; cfg.httpCookieStorage = nil
        cfg.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: cfg, delegate: stream, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Outcome<Void>, Never>) in
                stream.state.with { $0.continuation = c }
                if Task.isCancelled { c.resume(returning: .failure(.cancelled("Download cancelled"))); stream.state.with { $0.continuation = nil }; return }
                task.resume()
            }
        } onCancel: { task.cancel() }
        if case .failure(let f) = result, case .cancelled = f { return result }
        if case .failure(let f) = result, f.isTransport, let untrusted = policy.untrustedFailure() { return .failure(untrusted) }
        return result
    }

    private func finish(_ result: Outcome<Void>) {
        let c = state.with { s -> CheckedContinuation<Outcome<Void>, Never>? in let c = s.continuation; s.continuation = nil; return c }
        c?.resume(returning: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { completionHandler(.cancel); fail(.network("Video download failed")); return }
        #if DEBUG
        Self.trace?("range \(start)-\(end.map(String.init) ?? "end") -> HTTP \(http.statusCode), Content-Range \(http.value(forHTTPHeaderField: "Content-Range") ?? "-"), Accept-Ranges \(http.value(forHTTPHeaderField: "Accept-Ranges") ?? "-"), length \(http.expectedContentLength)")
        #endif
        switch http.statusCode {
        case 206: state.with { $0.position = start }
        case 200: state.with { $0.position = 0; $0.skip = start }
        case 416:
            // Asked past the end: nothing to send.
            state.with { $0.finishedEarly = true }; completionHandler(.cancel); return
        default:
            completionHandler(.cancel)
            fail(http.statusCode == 404 ? .notFound("Attachment not found") : .network("Video download failed (HTTP \(http.statusCode))")); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let (slice, done): (Data?, Bool) = state.with { s in
            let first = s.position, last = s.position + Int64(data.count) // [first, last)
            s.position = last
            var from = max(start, first), to = last
            if let end { to = min(to, end + 1) }
            let done = end.map { last > $0 } ?? false
            if from >= to { return (nil, done) }
            from -= first; to -= first
            return (data.subdata(in: Int(from)..<Int(to)), done)
        }
        #if DEBUG
        if let slice { Self.delivered.with { $0 += Int64(slice.count) } }
        #endif
        if let slice, !slice.isEmpty { onChunk?(slice) }
        if done { state.with { $0.finishedEarly = true }; dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (early, failure) = state.with { ($0.finishedEarly, $0.failure) }
        #if DEBUG
        Self.trace?("range \(start)-\(end.map(String.init) ?? "end") ended: \(error.map { ($0 as NSError).localizedDescription } ?? "complete")\(early ? " (stopped by us)" : "")")
        #endif
        if let failure { finish(.failure(failure)); return }
        if let error, !early {
            if (error as? URLError)?.code == .cancelled { finish(.failure(.cancelled("Download cancelled"))) }
            else { finish(.failure(.network("Video download failed: \((error as NSError).localizedDescription)"))) }
            return
        }
        finish(.success(()))
    }

    private func fail(_ f: Failure) { state.with { $0.failure = f } }
}

private extension Failure {
    var isTransport: Bool { if case .network = self { true } else { false } }
}
