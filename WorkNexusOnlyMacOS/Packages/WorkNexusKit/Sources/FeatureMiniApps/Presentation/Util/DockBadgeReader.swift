import AppKit
import ApplicationServices

/// New feature, no Dart counterpart. The badges the Dock shows on apps (unread counts), so the rail's Mac apps can show them too.
/// Reading them is reading the Dock's own interface, which macOS allows only to apps the user trusted under
/// Privacy & Security → Accessibility.
@MainActor
public protocol DockBadgeSource: AnyObject {
    /// Whether macOS lets this app read the Dock.
    var isAllowed: Bool { get }
    /// Asks macOS to show its "allow accessibility" prompt (it opens System Settings; the user ticks the app there).
    func requestAccess()
    /// Opens Privacy & Security → Accessibility in System Settings.
    func openSettings()
    /// The badge of each app in the Dock that has one, by the app's path and by `DockBadgeKey.bundle(id)` (the same app
    /// can be on the rail under another path: a link, another volume name). Empty when not allowed.
    func badges() -> [String: String]
    /// The same, read without keeping the main thread: the read that comes round every few seconds. The Dock answers
    /// some fifty questions each time, usually in a few milliseconds - and for as long as it likes while it is busy.
    func readBadges() async -> [String: String]
}

public extension DockBadgeSource {
    func readBadges() async -> [String: String] { badges() }
}

@MainActor
public final class DockBadgeReader: DockBadgeSource {
    public init() {}

    public var isAllowed: Bool { AXIsProcessTrusted() }

    public func requestAccess() {
        // The literal is `kAXTrustedCheckOptionPrompt`'s value (the constant is not concurrency-safe to read).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    public func badges() -> [String: String] { isAllowed ? Self.read() : [:] }

    public func readBadges() async -> [String: String] {
        guard isAllowed else { return [:] }
        return await Task.detached(priority: .utility) { Self.read() }.value
    }

    /// How long one question to the Dock may take, in seconds (macOS waits six by default).
    nonisolated static let answerWithin: Float = 1

    nonisolated static func read() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, answerWithin)
        var out: [String: String] = [:]
        // The Dock is one list of items; an app's item carries its file URL and, when it has a badge, a status label.
        for list in children(of: app) {
            for item in children(of: list) {
                guard let label = string(item, "AXStatusLabel"), !label.isEmpty, let url = attribute(item, kAXURLAttribute) else { continue }
                guard let path = (url as? URL)?.path ?? (url as? NSURL)?.path else { continue }
                out[normalized(path)] = label
                if let id = Bundle(path: path)?.bundleIdentifier { out[DockBadgeKey.bundle(id)] = label }
            }
        }
        return out
    }

    /// A bundle's path as both sides write it: no trailing slash.
    nonisolated static func normalized(_ path: String) -> String { path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    nonisolated private static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }
    nonisolated private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}

/// How a Dock badge is found for an app whose path the Dock writes differently.
public enum DockBadgeKey {
    public static func bundle(_ id: String) -> String { "bundle:" + id.lowercased() }
}
