import AppKit
import CoreDomain
import Foundation

/// An app starting or quitting, by bundle identifier.
public enum RunningAppEvent: Sendable, Equatable {
    case launched(String)
    case terminated(String)
}

/// New feature, no Dart counterpart. What the rail's Mac app buttons ask of the system, so tests never open a real app.
@MainActor
public protocol AppLauncher: AnyObject {
    /// The bundle identifiers of the apps running now.
    func runningBundleIds() -> Set<String>
    /// Opens the app at `path`, or — when it is already running — brings it forward and un-hides it.
    func launch(path: String, bundleId: String) async -> Outcome<Void>
    /// Shows the app's bundle in Finder.
    func reveal(path: String)
    /// Whether the `.app` is still where it was.
    func exists(path: String) -> Bool
    /// Apps starting and quitting from now on (one stream per call).
    func events() -> AsyncStream<RunningAppEvent>
}

/// `AppLauncher` over `NSWorkspace`: no Accessibility permission and no automation, only the public launch and activate calls.
@MainActor
public final class WorkspaceAppLauncher: AppLauncher {
    public init() {}

    public func runningBundleIds() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    public func launch(path: String, bundleId: String) async -> Outcome<Void> {
        guard exists(path: path) else { return .failure(.notFound("The app is not at \(path)")) }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first(where: { !$0.isTerminated }) {
            running.unhide()
            running.activate(options: [.activateAllWindows])
            return .success(())
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
            return .success(())
        } catch {
            return .failure(.unexpected(error.localizedDescription))
        }
    }

    public func reveal(path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }

    public func exists(path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    public func events() -> AsyncStream<RunningAppEvent> {
        AsyncStream { continuation in
            let center = NSWorkspace.shared.notificationCenter
            func watch(_ name: Notification.Name, _ make: @escaping @Sendable (String) -> RunningAppEvent) -> NSObjectProtocol {
                center.addObserver(forName: name, object: nil, queue: .main) { note in
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    if let id = app?.bundleIdentifier { continuation.yield(make(id)) }
                }
            }
            let tokens = [watch(NSWorkspace.didLaunchApplicationNotification) { .launched($0) },
                          watch(NSWorkspace.didTerminateApplicationNotification) { .terminated($0) }]
            nonisolated(unsafe) let kept = tokens
            continuation.onTermination = { _ in kept.forEach { center.removeObserver($0) } }
        }
    }
}
