import CoreDomain
import Observation
import SwiftUI

/// Ported from: lib/core/widgets/app_toast_controller.dart
/// What a toast reports: a done action, something to watch out for, or a failure.
public enum AppToastKind: Sendable { case success, warning, error

    /// How long a toast stays up: the more it needs reading, the longer.
    public var showFor: Duration {
        switch self { case .success: .milliseconds(2500); case .warning: .seconds(4); case .error: .seconds(5) }
    }
}

/// One toast on screen.
public struct AppToast: Identifiable, Equatable, Sendable {
    public let id: Int
    public let message: String
    public let kind: AppToastKind
    /// The label of the toast's one button (Undo), when it has one; what it does is kept by the controller.
    public var actionLabel: String? = nil

    /// How long it stays up: a toast with a button gives time to reach it.
    public var showFor: Duration { actionLabel == nil ? kind.showFor : max(kind.showFor, .seconds(8)) }
}

/// The toasts on screen, newest first, at most `maxShown`. Showing a message that is already up moves it to
/// the top instead of repeating it.
@MainActor @Observable
public final class AppToastController {
    public static let maxShown = 3
    public private(set) var toasts: [AppToast] = []
    private var nextId = 0
    @ObservationIgnored private var actions: [Int: @MainActor () -> Void] = [:]
    public init() {}

    /// Shows `message`; with `action`, the toast carries one button (`label`) that runs it and closes the toast.
    public func show(_ message: String, kind: AppToastKind = .success, action: (label: String, run: @MainActor () -> Void)? = nil) {
        // A failure the user was shown is a failure worth tracing.
        if kind == .error { Diagnostics.error("ui", message) }
        let t = AppToast(id: nextId, message: message, kind: kind, actionLabel: action?.label)
        if let action { actions[nextId] = action.run }
        nextId += 1
        toasts = Array(([t] + toasts.filter { $0.message != message }).prefix(Self.maxShown))
        let shown = Set(toasts.map(\.id))
        actions = actions.filter { shown.contains($0.key) }
    }

    /// Runs the button of toast `id` and closes it.
    public func runAction(_ id: Int) {
        let run = actions[id]
        dismiss(id)
        run?()
    }

    public func dismiss(_ id: Int) {
        actions[id] = nil
        let left = toasts.filter { $0.id != id }
        if left.count != toasts.count { toasts = left }
    }
}

private struct ToastsKey: EnvironmentKey { static let defaultValue: AppToastController? = nil }
public extension EnvironmentValues {
    /// The app's toast controller, set by `.toastHost(_:)` (Flutter: `AppToasts.maybeOf`).
    var toasts: AppToastController? {
        get { self[ToastsKey.self] }
        set { self[ToastsKey.self] = newValue }
    }
}

/// Ported from: lib/core/widgets/app_toast_card.dart
/// A compact toast: a card with a status glyph and the message. It slides in, goes away by itself (held while the
/// pointer is on it), and a click dismisses it. A warning or an error is tinted and shows a close mark.
struct AppToastCard: View {
    @Environment(\.appTheme) private var theme
    let toast: AppToast; let onDismiss: () -> Void
    var onAction: () -> Void = {}
    @State private var shown = false
    @State private var hovering = false

    var body: some View {
        let c = theme.colors
        let (glyph, tint): (String, Color) = switch toast.kind {
        case .success: ("checkmark.circle", c.green)
        case .warning: ("exclamationmark.triangle", c.amber)
        case .error: ("exclamationmark.circle", c.red)
        }
        let flagged = toast.kind != .success
        HStack(spacing: theme.spacing.s8) {
            Image(systemName: glyph).font(.system(size: theme.sizes.icon16)).foregroundStyle(tint)
            Text(toast.message).font(theme.typography.body).foregroundStyle(c.tx).fixedSize(horizontal: false, vertical: true)
            if let label = toast.actionLabel {
                Button(label, action: onAction).buttonStyle(.plain).font(theme.typography.bodyStrong).foregroundStyle(c.accent)
                    .pointerStyle(.link)
            }
            if flagged { Image(systemName: "xmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx2) }
        }
        .padding(.leading, theme.spacing.s16).padding(.trailing, flagged ? theme.spacing.s8 : theme.spacing.s16)
        .padding(.vertical, theme.spacing.s8)
        .appGlass(in: RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous),
                  tint: flagged ? tint.opacity(0.25) : nil, fallback: flagged ? tint.opacity(0.12) : c.card)
        .shadow(color: c.scrim.opacity(0.2), radius: theme.spacing.s6, y: theme.spacing.s2)
        .opacity(shown ? 1 : 0).offset(y: shown ? 0 : -theme.spacing.s8)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onDismiss)
        .pointerStyle(.link)
        .task(id: hovering) {
            if !shown { withAnimation(.easeOut(duration: theme.motion.base)) { shown = true } }
            guard !hovering else { return }
            try? await Task.sleep(for: toast.showFor)
            if !Task.isCancelled { onDismiss() }
        }
    }
}

/// Ported from: lib/core/widgets/app_toast_host.dart (`AppToastLayer`)
/// Draws the toasts at the top centre, under the title bar, clear of the inputs along the bottom. Only the toasts
/// take the pointer; everything around them stays clickable.
public struct AppToastHost: ViewModifier {
    @Environment(\.appTheme) private var theme
    let controller: AppToastController

    public func body(content: Content) -> some View {
        content
            .environment(\.toasts, controller)
            .overlay(alignment: .top) {
                VStack(spacing: theme.spacing.s8) {
                    ForEach(controller.toasts) { t in
                        AppToastCard(toast: t, onDismiss: { controller.dismiss(t.id) }, onAction: { controller.runAction(t.id) }).id(t.id)
                    }
                }
                .frame(maxWidth: theme.sizes.dialogSm)
                .padding(.top, theme.sizes.titleBar + theme.spacing.s10)
                .animation(.easeOut(duration: theme.motion.base), value: controller.toasts)
            }
            .onChange(of: controller.toasts.count, initial: true) { _, n in RepeatedClickLog.shared.mark("toast", up: n > 0) }
    }
}

public extension View {
    /// Hosts `controller`'s toasts over this view and publishes it as `\.toasts`.
    func toastHost(_ controller: AppToastController) -> some View { modifier(AppToastHost(controller: controller)) }
}
