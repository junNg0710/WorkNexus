/// Not in the Flutter app.
import AppKit
import Observation
import QuartzCore
import SwiftUI

/// What the screen showed over one second: how many frames the app drew, and the longest wait between two of them.
public struct FpsReading: Equatable, Sendable {
    public var fps: Int
    /// The longest gap between two frames, in ms (16–17 is a steady 60).
    public var worstMs: Int
    /// The display's own rate (60, 120).
    public var displayFps: Int

    /// Counts the frames of `gaps` (seconds between consecutive display ticks): a tick the main thread was late for
    /// stands for the frames it missed, so a held-up second reads low.
    public init(gaps: [Double], frame: Double) {
        let total = gaps.reduce(0, +)
        fps = total > 0 ? Int((Double(gaps.count) / total).rounded()) : 0
        worstMs = Int(((gaps.max() ?? 0) * 1000).rounded())
        displayFps = frame > 0 ? Int((1 / frame).rounded()) : 60
    }

    public enum Grade: Equatable { case smooth, uneven, slow }

    /// Smooth near the display's rate with no long frame; slow under half of it or with a frame held over 100 ms.
    public var grade: Grade {
        let share = Double(fps) / Double(max(displayFps, 1))
        if share < 0.5 || worstMs >= 100 { return .slow }
        if share < 0.85 || worstMs >= 34 { return .uneven }
        return .smooth
    }
}

/// Counts the frames the app draws, for the "Show FPS" badge (Settings › Local data › Diagnostics). It ticks with the
/// display while on and the app is in front, and publishes one reading a second, so the badge itself costs one small
/// redraw a second.
@MainActor @Observable
public final class FpsMeter: NSObject {
    public static let shared = FpsMeter()
    public private(set) var isOn = false
    public private(set) var reading: FpsReading?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var last: CFTimeInterval?
    @ObservationIgnored private var gaps: [Double] = []
    @ObservationIgnored private var elapsed = 0.0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if on {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resume() }
                },
                center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pause() }
                },
            ]
            if NSApp?.isActive ?? true { resume() }
        } else {
            pause()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            reading = nil
        }
    }

    private func resume() {
        guard isOn, link == nil, let screen = NSScreen.main else { return }
        let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l; last = nil; gaps = []; elapsed = 0
    }

    private func pause() { link?.invalidate(); link = nil; last = nil }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard let last else { return }
        let gap = link.timestamp - last
        gaps.append(gap); elapsed += gap
        guard elapsed >= 1 else { return }
        let next = FpsReading(gaps: gaps, frame: link.duration)
        if next != reading { reading = next }
        gaps = []; elapsed = 0
    }
}

/// The badge over the title bar while "Show FPS" is on: "58 fps · 21 ms", green when smooth, amber when uneven, red when
/// slow. It takes no clicks.
public struct FpsBadge: View {
    @Environment(\.appTheme) private var theme
    private let meter = FpsMeter.shared
    public init() {}

    public var body: some View {
        if meter.isOn {
            let r = meter.reading
            let c = theme.colors
            let tint: Color = switch r?.grade { case .smooth?: c.green; case .uneven?: c.amber; case .slow?: c.red; case nil: c.tx3 }
            HStack(spacing: theme.spacing.s6) {
                Circle().fill(tint).frame(width: theme.spacing.s6, height: theme.spacing.s6)
                Text(verbatim: r.map { "\($0.fps) fps · \($0.worstMs) ms" } ?? "– fps").font(theme.typography.mono).foregroundStyle(c.tx)
                    .monospacedDigit()
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s2)
            .background(c.card.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(c.line, lineWidth: theme.borders.hairline))
            .help(appString("fpsBadgeHelp", "Frames drawn in the last second, and the longest wait between two of them"))
            .allowsHitTesting(false)
        }
    }
}
