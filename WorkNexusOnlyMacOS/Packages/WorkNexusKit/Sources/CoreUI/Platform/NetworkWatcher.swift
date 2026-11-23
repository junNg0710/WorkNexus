/// Not in the Flutter app.
import CoreDomain
import Foundation
import Network

/// Keeps `Connectivity` in step with what macOS says about the network.
public final class NetworkWatcher: @unchecked Sendable {
    public static let shared = NetworkWatcher()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.worknexus.network")
    private var started = false

    /// Starts watching. Idempotent.
    public func start() {
        queue.sync {
            guard !started else { return }
            started = true
            // Only "no route at all" counts as offline: a path that still has to be brought up is given its chance.
            monitor.pathUpdateHandler = { path in Connectivity.set(online: path.status != .unsatisfied) }
            monitor.start(queue: queue)
        }
    }
}
