import Observation
import SwiftUI

/// Window-level home for dialogs. `.appDialog(...)` used to overlay only the view it was attached to, so a dialog opened
/// from a small container (the 78pt rail's "Add") was clipped to it. With a `DialogCenter` in the environment, dialogs are
/// registered here and drawn by `dialogHost` over the whole window instead.
@MainActor @Observable
public final class DialogCenter {
    struct Entry: Identifiable {
        let id: UUID
        let dismissOnScrim: Bool
        let content: () -> AnyView
        let dismiss: () -> Void
    }
    private(set) var stack: [Entry] = []
    public init() {}

    func present(_ entry: Entry) { stack.removeAll { $0.id == entry.id }; stack.append(entry) }
    func remove(_ id: UUID) { stack.removeAll { $0.id == id } }
}

private struct DialogCenterKey: EnvironmentKey { static let defaultValue: DialogCenter? = nil }
public extension EnvironmentValues {
    var dialogCenter: DialogCenter? {
        get { self[DialogCenterKey.self] }
        set { self[DialogCenterKey.self] = newValue }
    }
}

struct DialogHost: ViewModifier {
    @Environment(\.appTheme) private var theme
    let center: DialogCenter

    func body(content: Content) -> some View {
        content
            .environment(\.dialogCenter, center)
            .overlay {
                ForEach(center.stack) { entry in
                    ZStack {
                        theme.colors.scrim.opacity(0.45).ignoresSafeArea()
                            .onTapGesture { if entry.dismissOnScrim { entry.dismiss() } }
                        entry.content().padding(theme.spacing.s24)
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .animation(.easeOut(duration: theme.motion.base), value: center.stack.map(\.id))
            .onChange(of: center.stack.count, initial: true) { _, n in RepeatedClickLog.shared.mark("dialog", up: n > 0) }
    }
}

public extension View {
    /// Draws every dialog registered with `center` over this view (call once, at the window root).
    func dialogHost(_ center: DialogCenter) -> some View { modifier(DialogHost(center: center)) }
}
