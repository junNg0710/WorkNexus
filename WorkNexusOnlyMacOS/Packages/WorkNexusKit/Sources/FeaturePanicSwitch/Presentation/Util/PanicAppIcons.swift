import AppKit
import SwiftUI

/// Not in the Flutter app (its pickers showed names only). An app's Dock icon by bundle identifier, found through
/// LaunchServices once and kept for the session; nil when the app is not installed.
@MainActor
enum PanicAppIcons {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func image(for bundleId: String) -> Image? {
        if let hit = cache[bundleId] { return Image(nsImage: hit) }
        guard !missing.contains(bundleId) else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            missing.insert(bundleId)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleId] = icon
        return Image(nsImage: icon)
    }
}
