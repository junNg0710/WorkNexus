import CoreDomain
import Foundation

/// Minimal WebSocket surface the xxd connection needs, so tests can swap in a fake server.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_socket.dart
public protocol XxdSocket: AnyObject, Sendable {
    /// Incoming frames; finishes (or throws) when the socket closes.
    var frames: AsyncThrowingStream<XxdFrame, Error> { get }
    func send(_ frame: XxdFrame) async throws
    func close(code: Int?, reason: String?) async
    var closeCode: Int? { get }
    var closeReason: String? { get }
}

/// Opens a socket to a URL using the pinning policy for the TLS handshake.
public typealias XxdSocketConnector = @Sendable (URL, XxdTLSPolicy) async throws -> XxdSocket

/// Production socket over `URLSessionWebSocketTask`.
public final class URLSessionXxdSocket: NSObject, XxdSocket, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let policy: XxdTLSPolicy
    private var session: URLSession!
    private var task: URLSessionWebSocketTask!
    private let lock = NSLock()
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var opened = false
    private var openError: Error?
    private var continuation: AsyncThrowingStream<XxdFrame, Error>.Continuation?
    private var _code: Int?
    private var _reason: String?
    public let frames: AsyncThrowingStream<XxdFrame, Error>

    public var closeCode: Int? { lock.lock(); defer { lock.unlock() }; return _code }
    public var closeReason: String? { lock.lock(); defer { lock.unlock() }; return _reason }

    private init(policy: XxdTLSPolicy) {
        self.policy = policy
        var cont: AsyncThrowingStream<XxdFrame, Error>.Continuation!
        frames = AsyncThrowingStream(bufferingPolicy: .unbounded) { cont = $0 }
        continuation = cont
        super.init()
    }

    /// Connects, waiting up to `timeout` seconds for the handshake.
    public static func connect(_ url: URL, policy: XxdTLSPolicy, timeout: TimeInterval = 20) async throws -> URLSessionXxdSocket {
        let socket = URLSessionXxdSocket(policy: policy)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        socket.session = URLSession(configuration: cfg, delegate: socket, delegateQueue: nil)
        socket.task = socket.session.webSocketTask(with: url)
        socket.task.maximumMessageSize = 64 * 1024 * 1024
        socket.task.resume()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await socket.waitOpen() }
                group.addTask { try await Task.sleep(nanoseconds: UInt64(timeout * 1e9)); throw URLError(.timedOut) }
                _ = try await group.next()
                group.cancelAll()
            }
        } catch {
            socket.task.cancel(with: .goingAway, reason: nil)
            socket.session.invalidateAndCancel()
            throw xxdMapTransportError(error, policy: policy, fallback: "Cannot open the chat socket")
        }
        socket.receiveLoop()
        return socket
    }

    private func waitOpen() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock()
            if opened { lock.unlock(); c.resume(); return }
            if let e = openError { lock.unlock(); c.resume(throwing: e); return }
            openContinuation = c
            lock.unlock()
        }
    }

    private func receiveLoop() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let s): self.continuation?.yield(.text(s))
                case .data(let d): self.continuation?.yield(.binary(d))
                @unknown default: break
                }
                self.receiveLoop()
            case .failure(let e):
                self.finish(error: e)
            }
        }
    }

    private func finish(error: Error?) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        if let error { c?.finish(throwing: error) } else { c?.finish() }
    }

    public func send(_ frame: XxdFrame) async throws {
        switch frame {
        case .text(let s): try await task.send(.string(s))
        case .binary(let d): try await task.send(.data(d))
        }
    }

    public func close(code: Int? = 1000, reason: String? = nil) async {
        task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code ?? 1000) ?? .normalClosure, reason: reason?.data(using: .utf8))
        finish(error: nil)
        session.finishTasksAndInvalidate()
    }

    // MARK: delegate

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        lock.lock(); opened = true; let c = openContinuation; openContinuation = nil; lock.unlock()
        c?.resume()
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.lock(); _code = closeCode.rawValue; _reason = reason.flatMap { String(data: $0, encoding: .utf8) }; lock.unlock()
        finish(error: nil)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let c = openContinuation; openContinuation = nil
        if !opened, let error { openError = error }
        lock.unlock()
        if let error { c?.resume(throwing: error); finish(error: error) } else { finish(error: nil) }
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { completionHandler(.performDefaultHandling, nil); return }
        if let cred = policy.evaluate(trust: trust, host: challenge.protectionSpace.host) { completionHandler(.useCredential, cred) }
        else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        self.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
}

/// Production connector.
public let urlSessionXxdConnector: XxdSocketConnector = { url, policy in
    try await URLSessionXxdSocket.connect(url, policy: policy)
}
