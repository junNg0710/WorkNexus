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
    /// The badge of each app in the Dock that has one, by the app's path. Empty when not allowed.
    func badges() -> [String: String]
}

@MainActor
public final class DockBadgeReader: DockBadgeSource {
    public init() {}

    public var isAllowed: Bool { AXIsProcessTrusted() }

    public func requestAccess() {
        // The literal is `kAXTrustedCheckOptionPrompt`'s value (the constant is not concurrency-safe to read).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func badges() -> [String: String] {
        guard isAllowed, let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var out: [String: String] = [:]
        // The Dock is one list of items; an app's item carries its file URL and, when it has a badge, a status label.
        for list in children(of: app) {
            for item in children(of: list) {
                guard let label = string(item, "AXStatusLabel"), !label.isEmpty, let url = attribute(item, kAXURLAttribute) else { continue }
                let path = (url as? URL)?.path ?? (url as? NSURL)?.path
                if let path { out[Self.normalized(path)] = label }
            }
        }
        return out
    }

    /// A bundle's path as both sides write it: no trailing slash.
    static func normalized(_ path: String) -> String { path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }
    private func children(of element: AXUIElement) -> [AXUIElement] { (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
}
