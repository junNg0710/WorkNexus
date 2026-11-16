import CoreDomain
import Foundation
import Observation

/// New (no Dart counterpart): keeps the session cookies of the mini apps' sites (and of the imported ones) from one run to
/// the next. WebKit forgets a cookie without an expiry when the app quits, and that is where many sites keep the sign-in.
///
/// `start()` puts the kept cookies back into the web view — a mini app's first page waits for that (`ready()`) — and then
/// copies them out again a moment after every change of the web view's cookies, so a crash loses nothing; `stop()` takes a
/// last copy as the app quits.
@MainActor
public final class SessionCookieKeeper {
    enum State { case idle, restoring, ready, stopped }

    /// Changes come in bursts (a page sets a dozen cookies while it loads): one copy after they settle.
    nonisolated static let debounce: Duration = .seconds(2)
    /// A page never waits longer than this for the kept cookies.
    nonisolated static let readyTimeout: Duration = .seconds(5)

    private(set) var state = State.idle
    private let restore: RestoreSessionCookies
    private let snapshot: SnapshotSessionCookies
    private let forget: ForgetSessionCookies
    private let changes: @Sendable () -> AsyncStream<Void>
    private let debounce: Duration
    private var last: [BrowserCookie]?
    private var watching: Task<Void, Never>?
    private var pending: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(restore: RestoreSessionCookies, snapshot: SnapshotSessionCookies, forget: ForgetSessionCookies,
         changes: @escaping @Sendable () -> AsyncStream<Void>, debounce: Duration = SessionCookieKeeper.debounce) {
        self.restore = restore; self.snapshot = snapshot; self.forget = forget; self.changes = changes; self.debounce = debounce
    }

    /// Whether a page may load: the kept cookies are back (or the keeper was never started, as in a test).
    var isReady: Bool { state != .restoring }

    /// Starts restoring, then watching. Call once at launch, before any mini app's page exists.
    public func start() {
        guard state == .idle else { return }
        state = .restoring
        Task { [weak self] in
            guard let self else { return }
            if case .success(let kept) = await self.restore() { self.last = kept }
            guard self.state == .restoring else { return }
            self.state = .ready
            self.release()
            self.watch()
        }
    }

    /// Resolves once the kept cookies are back in the web view — at once when they already are — or after `readyTimeout`.
    func ready() async {
        guard state == .restoring else { return }
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.readyTimeout)
            if !Task.isCancelled { self?.release() }
        }
        await withCheckedContinuation { waiters.append($0) }
        timeout.cancel()
    }

    private func release() {
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume() }
    }

    private func watch() {
        let changes = changes
        watching = Task { [weak self] in
            for await _ in changes() { self?.snapshotSoon() }
        }
    }

    /// Copies the cookies out once they have settled.
    func snapshotSoon() {
        guard state == .ready else { return }
        pending?.cancel()
        let delay = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { await self?.snapshotNow() }
        }
    }

    /// Copies the cookies out now (a mini app was removed, an imported site forgotten, a site's data cleared).
    func snapshotNow() async {
        guard state == .ready else { return }
        if case .success(let kept) = await snapshot(previous: last) { last = kept }
    }

    /// "Clear all browsing data": nothing is kept any more.
    func forgetAll() async {
        pending?.cancel()
        if case .success = await forget() { last = [] }
    }

    /// The app quits: a last copy. An empty answer at this point (the web view may be gone) never wipes what is kept.
    public func stop() async {
        guard state == .ready else { state = .stopped; release(); return }
        pending?.cancel(); watching?.cancel()
        if case .success(let kept) = await snapshot(previous: last, allowEmpty: false) { last = kept }
        state = .stopped
    }
}
