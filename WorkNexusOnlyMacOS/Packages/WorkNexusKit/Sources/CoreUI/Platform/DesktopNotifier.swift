import Foundation
import UserNotifications

/// Ported from: lib/core/platform/desktop_notifier.dart
/// OS notifications so the rest of the app never imports UserNotifications. `taps` emits the payload of a
/// notification the user clicked.
public protocol DesktopNotifying: Sendable {
    /// One stream per call; every subscriber sees every tap.
    var taps: AsyncStream<String> { get }
    /// Sets things up (macOS asks for permission the first time). False where notifications are unavailable;
    /// `show` then no-ops.
    func initialize() async -> Bool
    /// False when notifications or their banners are turned off for the app, nil when that cannot be known.
    func permissionGranted() async -> Bool?
    /// macOS only shows its prompt once; after the user declined it can only be changed in System Settings.
    func requestPermission() async -> Bool
    func openSystemSettings()
    /// One with the same `id` replaces the previous one (e.g. one per conversation).
    func show(id: Int, title: String, body: String, payload: String?) async
}

public final class DesktopNotifier: NSObject, DesktopNotifying, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<String>.Continuation] = [:]
    private var ready = false
    private let bundleId: String

    public init(bundleId: String = AppIdentity.bundleId) { self.bundleId = bundleId; super.init() }

    /// `UNUserNotificationCenter.current()` traps outside an app bundle (tests, command-line tools).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    public var taps: AsyncStream<String> {
        AsyncStream { cont in
            let id = UUID()
            lock.lock(); subscribers[id] = cont; lock.unlock()
            cont.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.subscribers[id] = nil; self?.lock.unlock()
            }
        }
    }

    public func initialize() async -> Bool {
        if lock.withLock({ ready }) { return true }
        guard let center else { return false }
        center.delegate = self
        // Badge permission is asked too: macOS hides the Dock badge of unread chats without it.
        let ok = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        // Not cached when it failed: permission may be granted in System Settings later, and the next message tries again.
        lock.withLock { ready = ok }
        return ok
    }

    public func permissionGranted() async -> Bool? {
        guard let center else { return nil }
        let s = await center.notificationSettings()
        let on = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
        return on && s.alertSetting == .enabled
    }

    public func requestPermission() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    public func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [url.absoluteString]
        try? p.run()
    }

    public func show(id: Int, title: String, body: String, payload: String?) async {
        guard await initialize(), let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        if let payload { content.userInfo = ["payload": payload] }
        // Same identifier replaces the earlier notification.
        let request = UNNotificationRequest(identifier: "worknexus.\(id)", content: content, trigger: nil)
        // Not worth interrupting the user over a failure; the unread badge still shows.
        try? await center.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shown even while the app is frontmost (the Flutter plugin's default presentation).
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                       withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                       withCompletionHandler done: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let payload = response.notification.request.content.userInfo["payload"] as? String {
            lock.lock(); let subs = Array(subscribers.values); lock.unlock()
            for s in subs { s.yield(payload) }
        }
        done()
    }
}
