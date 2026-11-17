/// Not in the Flutter app (its boards were read again only on demand).
import AppKit
import CoreUI
import SwiftUI

/// Keeps the Tasks and Bugs boards current while they are looked at: new and changed tickets are picked up when the app
/// comes back to the front and every few minutes while a board is on screen. Nothing is read while the window is hidden.
struct ZentaoAutoRefresh: ViewModifier {
    let state: ZentaoUIState
    @Environment(\.sectionIsActive) private var sectionActive
    /// How often a board on screen is read again.
    static let interval: Duration = .seconds(180)
    /// Coming back to the app reads again only when the last read is at least this old (switching apps often).
    static let resumeGap: TimeInterval = 30
    @State private var lastRun = Date()

    func body(content: Content) -> some View {
        content
            .task(id: sectionActive) {
                guard sectionActive else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.interval)
                    if Task.isCancelled { return }
                    if AppVisibility.isOnScreen { await run() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard sectionActive, Date().timeIntervalSince(lastRun) >= Self.resumeGap else { return }
                Task { await run() }
            }
    }

    private func run() async {
        lastRun = Date()
        await state.refreshShownBoards()
    }
}

extension View {
    func zentaoAutoRefresh(_ state: ZentaoUIState) -> some View { modifier(ZentaoAutoRefresh(state: state)) }
}
