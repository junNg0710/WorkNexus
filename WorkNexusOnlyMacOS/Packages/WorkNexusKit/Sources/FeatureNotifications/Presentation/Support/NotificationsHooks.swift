import AppKit
import CoreDomain
import CoreUI
import Foundation

/// The app-level side effects the notifications model needs, injected by the composition root so the model stays
/// testable and never reaches into the shell (Flutter: `appNavProvider`, `DesktopWindowService`, `showAppSnack`).
public struct NotificationsHooks {
    /// Opens a ticket (WorkNexus ticket id) in the detail slide-over (`AppNavController.openTicket`).
    public var openTicket: @MainActor (String) -> Void
    /// Opens a link in the browser; false when it could not be opened.
    public var openURL: @MainActor (String) -> Bool
    public var toast: @MainActor (String, AppToastKind) -> Void
    /// Whether the app window is frontmost and focused.
    public var isAppFocused: @MainActor () async -> Bool
    public var bringToFront: @MainActor () -> Void

    public init(openTicket: @escaping @MainActor (String) -> Void,
                openURL: @escaping @MainActor (String) -> Bool = { openLinkExternally($0, inApp: false) },
                toast: @escaping @MainActor (String, AppToastKind) -> Void = { _, _ in },
                isAppFocused: @escaping @MainActor () async -> Bool = { NSApp?.isActive == true && NSApp?.keyWindow != nil },
                bringToFront: @escaping @MainActor () -> Void = {
                    NSApp?.activate()
                    NSApp?.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                }) {
        self.openTicket = openTicket; self.openURL = openURL; self.toast = toast
        self.isAppFocused = isAppFocused; self.bringToFront = bringToFront
    }
}
