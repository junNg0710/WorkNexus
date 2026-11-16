import CoreDomain
import Foundation

/// One HTTPS exchange through the pinning policy: streams the response (progress), reports upload progress, can be
/// cancelled through a `ChatCancelToken`, and optionally refuses to follow redirects (the im-authorize flow does it by hand).
final class XxdHTTPTransport: XxdPinningDelegate, URLSessionDataDelegate, @unchecked Sendable {
    struct Output { var data: Data; var response: HTTPURLResponse }

    private let followRedirects: Bool
    private let onReceived: (@Sendable (Int, Int?) -> Void)?
    private let onSent: (@Sendable (Double) -> Void)?
    private var buffer = Data()
    private var http: HTTPURLResponse?
    private var continuation: CheckedContinuation<Output, Error>?
    private let lock = NSLock()

    init(policy: XxdTLSPolicy, followRedirects: Bool = true,
         onReceived: (@Sendable (Int, Int?) -> Void)? = nil, onSent: (@Sendable (Double) -> Void)? = nil) {
        self.followRedirects = followRedirects; self.onReceived = onReceived; self.onSent = onSent
        super.init(policy: policy)
    }

    /// Runs `request` (body in memory or streamed from `bodyFile`).
    func run(_ request: URLRequest, bodyFile: URL? = nil, cancel: ChatCancelToken? = nil) async throws -> Output {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil
        cfg.timeoutIntervalForRequest = request.timeoutInterval
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = bodyFile.map { session.uploadTask(with: request, fromFile: $0) } ?? session.dataTask(with: request)
        let hook = cancel?.onCancel { task.cancel() }
        defer { if let hook { cancel?.removeHandler(hook) } }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Output, Error>) in
                lock.lock(); continuation = c; lock.unlock()
                task.resume()
            }
        } onCancel: { task.cancel() }
    }

    private func finish(_ result: Result<Output, Error>) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        http = response as? HTTPURLResponse
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        let expected = dataTask.countOfBytesExpectedToReceive
        onReceived?(buffer.count, expected > 0 ? Int(expected) : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { onSent?(Double(totalBytesSent) / Double(totalBytesExpectedToSend)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(followRedirects ? request : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        guard let http = http ?? (task.response as? HTTPURLResponse) else { finish(.failure(URLError(.badServerResponse))); return }
        finish(.success(Output(data: buffer, response: http)))
    }
}
