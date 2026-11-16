import AppKit
import Foundation

/// Ported from: lib/core/platform/window_placement_store.dart + window_placement_recorder.dart
/// Where the app window was when last used (maximized or not, plus its frame), in a small JSON file in Application
/// Support. It is read before the window is shown — before the database and the rest of the app are set up — so it does
/// not live in the DB.
public struct WindowPlacement: Codable, Equatable, Sendable {
    public var maximized: Bool
    public var x: Double?, y: Double?, width: Double?, height: Double?
    public init(maximized: Bool = true, frame: CGRect? = nil) {
        self.maximized = maximized
        x = frame.map { Double($0.origin.x) }; y = frame.map { Double($0.origin.y) }
        width = frame.map { Double($0.width) }; height = frame.map { Double($0.height) }
    }
    public var frame: CGRect? {
        guard let x, let y, let width, let height, width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct WindowPlacementStore: Sendable {
    private let file: URL
    public static let fileName = "window_placement.json"

    public init(directory: URL = PlatformPaths.applicationSupport()) {
        file = directory.appendingPathComponent(Self.fileName)
    }

    /// Defaults to maximized on the first run or when the file cannot be read.
    public func read() -> WindowPlacement {
        guard let data = try? Data(contentsOf: file), let p = try? JSONDecoder().decode(WindowPlacement.self, from: data) else {
            return WindowPlacement()
        }
        return p
    }

    public func readMaximized() -> Bool { read().maximized }

    public func write(_ placement: WindowPlacement) {
        // Only the next launch opening the same way is lost on failure.
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(placement) else { return }
        try? data.write(to: file, options: .atomic)
    }

    public func writeMaximized(_ maximized: Bool) {
        var p = read(); p.maximized = maximized; write(p)
    }
}

/// Saves the window's zoomed state and frame each time they change (debounced), so the next launch opens it the same
/// way. Full screen is left out: it is entered for a video, not as a way of using the app.
@MainActor
public final class WindowPlacementRecorder {
    private let store: WindowPlacementStore
    private var tokens: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    public init(store: WindowPlacementStore = WindowPlacementStore()) { self.store = store }

    /// Restores the saved placement on `window` and starts recording its changes.
    public func attach(to window: NSWindow, restore: Bool = true) {
        if restore { Self.apply(store.read(), to: window) }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] n in
                MainActor.assumeIsolated { if let w = n.object as? NSWindow { self?.schedule(w) } }
            })
        }
    }

    public func detach() {
        tokens.forEach(NotificationCenter.default.removeObserver); tokens = []
        pending?.cancel()
    }

    public static func apply(_ p: WindowPlacement, to window: NSWindow) {
        if let frame = p.frame, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            window.setFrame(frame, display: false)
        }
        if p.maximized, !window.isZoomed { window.zoom(nil) }
    }

    private func schedule(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        pending?.cancel()
        pending = Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, let window else { return }
            // While zoomed the frame is the screen's; keep the last normal frame instead.
            var p = self.store.read()
            p.maximized = window.isZoomed
            if !window.isZoomed { p = WindowPlacement(maximized: false, frame: window.frame) }
            self.store.write(p)
        }
    }
}
