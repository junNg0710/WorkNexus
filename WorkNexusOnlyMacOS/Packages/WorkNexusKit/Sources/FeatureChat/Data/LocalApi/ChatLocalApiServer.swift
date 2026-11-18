import CoreDomain
import Foundation
import Network

/// The localhost HTTP endpoint local tools (an AI assistant's MCP server) use chat through, so they reuse this app's
/// signed-in session instead of holding the user's ZenTao password themselves.
///
/// Listens on 127.0.0.1 only, on a free port, and answers only requests that carry the bearer token written — with the port
/// and this process's id — to `chat_local_api.json` in `directory` (a file only the user can read; see
/// `LocalApiDiscoveryFile`). A new token is made at every start; it lives in memory and in that file only, never in the
/// database or the log. Requests are answered by `ChatLocalApiRouter`; nothing about them (message text included) is logged.
/// Ported from: lib/features/chat/data/datasources/chat_local_api_server.dart, data/repositories/server_chat_local_api.dart
public actor ChatLocalApiServer: ChatLocalApi {
    public static let discoveryFileName = LocalApiDiscoveryFile.fileName
    static let maxBodyBytes = 64 * 1024

    /// Where the discovery file goes: beside the database.
    public nonisolated let directory: URL
    private let processId: Int32
    private let makeToken: @Sendable () -> String
    private let queue = DispatchQueue(label: "com.worknexus.chat-local-api")
    private var listener: NWListener?
    private var opening: Task<Outcome<Void>, Never>?
    private var generation = 0
    private var handlers: ChatLocalApiHandlers?
    private var token = ""
    /// The port it listens on while running.
    public private(set) var port: UInt16?

    public init(directory: URL, processId: Int32 = ProcessInfo.processInfo.processIdentifier,
                makeToken: @escaping @Sendable () -> String = ChatLocalApiServer.randomToken) {
        self.directory = directory; self.processId = processId; self.makeToken = makeToken
    }

    public var isRunning: Bool { listener != nil }

    public func start(_ handlers: ChatLocalApiHandlers) async -> Outcome<Void> {
        self.handlers = handlers
        if listener != nil { return .success(()) }
        if let opening { return await opening.value }
        let task = Task { await open(generation) }
        opening = task
        let result = await task.value
        opening = nil
        return result
    }

    public func stop() async -> Outcome<Void> {
        generation += 1
        handlers = nil; token = ""; port = nil
        listener?.cancel(); listener = nil
        LocalApiDiscoveryFile.remove(in: directory)
        return .success(())
    }

    /// Removes the discovery file at once — for app termination, where there is no time to await `stop()`. The MCP server
    /// would ignore a file left by a process that is gone anyway; this keeps the folder tidy.
    public nonisolated func removeDiscoveryFileNow() { LocalApiDiscoveryFile.remove(in: directory) }

    private func open(_ gen: Int) async -> Outcome<Void> {
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            listener = try NWListener(using: parameters)
        } catch {
            return .failure(.network("Could not open the local chat API: \(error.localizedDescription)"))
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        guard let port = await Self.ready(listener, on: queue) else {
            listener.cancel()
            return .failure(.network("Could not open the local chat API"))
        }
        guard gen == generation else { listener.cancel(); return .failure(.cancelled("Stopped while starting")) }
        let token = makeToken()
        do {
            try LocalApiDiscoveryFile.write(in: directory, port: port, token: token, pid: processId)
        } catch {
            listener.cancel()
            return .failure(.storage("Could not write the local chat API file"))
        }
        self.token = token; self.port = port; self.listener = listener
        return .success(())
    }

    /// Starts `listener` and waits until it listens; its port, or nil when it failed.
    private static func ready(_ listener: NWListener, on queue: DispatchQueue) async -> UInt16? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UInt16?, Never>) in
            let once = ResumeOnce(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(listener.port?.rawValue)
                case .failed, .cancelled: once.resume(nil)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    private nonisolated func accept(_ connection: NWConnection) {
        // Bound to 127.0.0.1, so only this computer reaches it; refuse anything else all the same.
        guard case .hostPort(let host, _) = connection.endpoint, Self.isLoopback(host) else { connection.cancel(); return }
        LocalApiConnection(connection: connection, queue: queue, maxBodyBytes: Self.maxBodyBytes) { [weak self] request in
            guard let self else { return ChatLocalApiRouter.error(503, "Stopping") }
            return await self.respond(to: request)
        }.start()
    }

    private func respond(to request: LocalHttpRequest) async -> LocalHttpResponse {
        await ChatLocalApiRouter.respond(to: request, token: token, handlers: handlers, maxBodyBytes: Self.maxBodyBytes)
    }

    static func isLoopback(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let a): return a.isLoopback
        case .ipv6(let a): return a.isLoopback || a == IPv6Address("::ffff:127.0.0.1")
        case .name(let n, _): return n == "localhost" || n == "127.0.0.1"
        @unknown default: return false
        }
    }

    /// 32 random bytes, base64url (as the Flutter app's `base64Url.encode`).
    public static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }
}

/// Resumes a continuation once, whichever state callback comes first.
private final class ResumeOnce<T>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Never>?
    private let lock = NSLock()
    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
    func resume(_ value: T) {
        let c: CheckedContinuation<T, Never>? = lock.withLock { defer { continuation = nil }; return continuation }
        c?.resume(returning: value)
    }
}

/// One client connection: reads one request, answers it, closes. A client that has not sent a whole request within
/// `timeout` is dropped, so a stuck connection does not linger.
private final class LocalApiConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let respond: @Sendable (LocalHttpRequest) async -> LocalHttpResponse
    private var reader: LocalHttpRequestReader
    private var answered = false
    private static let timeout: DispatchTimeInterval = .seconds(15)

    init(connection: NWConnection, queue: DispatchQueue, maxBodyBytes: Int,
         respond: @escaping @Sendable (LocalHttpRequest) async -> LocalHttpResponse) {
        self.connection = connection; self.queue = queue; self.respond = respond
        reader = LocalHttpRequestReader(maxBodyBytes: maxBodyBytes)
    }

    func start() {
        connection.stateUpdateHandler = { [connection] state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.timeout) { [self] in if !answered { connection.cancel() } }
        receive()
    }

    // Runs on `queue` (every NWConnection callback does), so `reader` and `answered` need no lock.
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                switch reader.feed(data) {
                case .needMore: break
                case .done(let request): return answer { await self.respond(request) }
                case .malformed(let reason): return answer { ChatLocalApiRouter.error(400, reason) }
                }
            }
            if error != nil || isComplete { connection.cancel(); return }
            receive()
        }
    }

    private func answer(_ make: @escaping @Sendable () async -> LocalHttpResponse) {
        answered = true
        let connection = connection
        Task {
            let response = await make()
            connection.send(content: response.serialized, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
