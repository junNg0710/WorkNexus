import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/app_update/presentation/providers/update_controller.dart
/// Keeps the app current in the background: looks for a newer stable release on `start()` and every `checkEvery`,
/// downloads and verifies it on its own, then holds it in `.ready` until the user asks to restart into it. With
/// automatic updates off it does none of that by itself — only `check()`, which the user asks for, looks.
@MainActor @Observable
public final class UpdateModel {
    public private(set) var state: UpdateState = .idle

    private let checkForUpdate: CheckForUpdate
    private let downloadUpdate: DownloadUpdate
    private let installUpdate: InstallUpdate
    private let autoUpdateEnabled: @Sendable () async -> Bool
    private let checkEvery: Duration
    @ObservationIgnored private var inFlight: Task<Outcome<AvailableUpdate?>, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Whether the user asked for the check in flight: what it finds is then downloaded whatever the setting says.
    @ObservationIgnored private var userAsked = false

    public init(checkForUpdate: CheckForUpdate, downloadUpdate: DownloadUpdate, installUpdate: InstallUpdate,
                checkEvery: Duration = .seconds(3600),
                autoUpdateEnabled: @escaping @Sendable () async -> Bool = { true }) {
        self.checkForUpdate = checkForUpdate; self.downloadUpdate = downloadUpdate; self.installUpdate = installUpdate
        self.checkEvery = checkEvery; self.autoUpdateEnabled = autoUpdateEnabled
    }

    /// Runs the first check right away, then every `checkEvery`. Idempotent.
    public func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkInBackground()
                guard let every = self?.checkEvery else { return }
                try? await Task.sleep(for: every)
            }
        }
    }

    public func stop() { timer?.cancel(); timer = nil }

    /// `check()`, unless the user turned automatic updates off.
    public func checkInBackground() async {
        guard await autoUpdateEnabled() else { return }
        _ = await shared()
    }

    /// Looks for a newer stable release and, when it has a build for this platform, starts downloading it. Returns what
    /// was found so a manual check can tell the user; a check already running is shared, not repeated.
    @discardableResult
    public func check() async -> Outcome<AvailableUpdate?> {
        userAsked = true
        return await shared()
    }

    private func shared() async -> Outcome<AvailableUpdate?> {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.run() }
        inFlight = task
        let result = await task.value
        inFlight = nil; userAsked = false
        return result
    }

    private func run() async -> Outcome<AvailableUpdate?> {
        let result = await checkForUpdate()
        if case .success(let update?) = result {
            // Automatic updates turned off while a background check ran: what it found waits for the user to ask.
            if userAsked { stage(update) } else if await autoUpdateEnabled() { stage(update) }
        }
        return result
    }

    /// Moves `update` towards `.ready` unless it is already on its way. A failed attempt is retried by the next check.
    private func stage(_ update: AvailableUpdate) {
        switch state {
        case .downloading, .installing: return
        case .ready(let u, _) where u.latestVersion == update.latestVersion: return
        default: break
        }
        guard update.canInstallInApp else { state = .manual(update); return }
        Task { await download(update) }
    }

    private func download(_ update: AvailableUpdate) async {
        state = .downloading(update, progress: 0)
        let progress = ProgressRelay { [weak self] p in Task { @MainActor in self?.report(update, p) } }
        switch await downloadUpdate(update, onProgress: { progress.send($0) }) {
        case .success(let path): state = .ready(update, stagedPath: path)
        case .failure(let f): state = .failed(update, message: f.message)
        }
    }

    private func report(_ update: AvailableUpdate, _ p: Double) {
        if case .downloading(_, let shown) = state, p - shown >= 0.01 { state = .downloading(update, progress: p) }
    }

    /// Only returns when the update could not be installed; on success the app quits and the new build starts.
    public func installAndRestart() async {
        guard case .ready(let update, let path) = state else { return }
        state = .installing(update)
        if case .failure(let f) = await installUpdate(stagedPath: path) { state = .failed(update, message: f.message) }
    }
}

/// Hops progress callbacks (any thread) onto the main actor.
private final class ProgressRelay: @unchecked Sendable {
    private let sink: @Sendable (Double) -> Void
    init(_ sink: @escaping @Sendable (Double) -> Void) { self.sink = sink }
    func send(_ p: Double) { sink(p) }
}
