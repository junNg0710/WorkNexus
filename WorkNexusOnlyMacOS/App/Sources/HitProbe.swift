import AppKit
import Foundation

#if DEBUG
/// DEBUG builds only: `WN_DEMO_HITS=1` asks, every three seconds, which AppKit view a click would land on at each point
/// of a grid over the window, and prints the views other than the window's own SwiftUI view that take some - with the
/// room each takes. A view kept hidden that still takes clicks shows up here, over the buttons it makes dead.
@MainActor
enum HitProbe {
    static func start() {
        guard ProcessInfo.processInfo.environment["WN_DEMO_HITS"] == "1" else { return }
        Task { @MainActor in
            var round = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                round += 1
                scan(round)
            }
        }
    }

    /// How much of `view` shows: the product of its own and its ancestors' alpha (0 for a hidden one).
    private static func alpha(_ view: NSView) -> CGFloat {
        var a: CGFloat = 1, v: NSView? = view
        while let cur = v { if cur.isHidden { return 0 }; a *= cur.alphaValue; v = cur.superview }
        return a
    }

    private static func scan(_ round: Int) {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }), let root = window.contentView else { return }
        var kinds: [String: Int] = [:]
        var unseen: [ObjectIdentifier: (name: String, frame: CGRect, count: Int)] = [:]
        let size = root.bounds.size, step: CGFloat = 8
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                // Window points from the top-left, as the click tools take them.
                let inRoot = root.isFlipped ? NSPoint(x: x, y: y) : NSPoint(x: x, y: size.height - y)
                if let hit = root.hitTest(root.convert(inRoot, to: root.superview)), hit !== root {
                    let name = String(describing: type(of: hit))
                    kinds[name, default: 0] += 1
                    // Takes the click and cannot be seen: what makes a button under it dead.
                    if name != "PlatformGroupContainer" {
                        let inWindow = hit.convert(hit.bounds, to: nil)
                        let frame = CGRect(x: inWindow.minX, y: window.contentLayoutRect.height - inWindow.maxY, width: inWindow.width, height: inWindow.height)
                        var u = unseen[ObjectIdentifier(hit)] ?? (name, frame, 0)
                        u.count += 1
                        unseen[ObjectIdentifier(hit)] = u
                    }
                }
                x += step
            }
            y += step
        }
        let all = kinds.sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
        let dead = unseen.values.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }.prefix(60).map {
            "\($0.name) ×\($0.count) at \(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))×\(Int($0.frame.height))"
        }
        print("HITS \(round) window \(Int(size.width))×\(Int(size.height)): \(all)")
        print("UNSEEN \(round): " + (dead.isEmpty ? "none" : dead.joined(separator: " | ")))
        fflush(stdout)
    }
}
#endif
