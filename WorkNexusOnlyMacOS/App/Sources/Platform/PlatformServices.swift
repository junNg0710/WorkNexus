import AppKit
import CoreDomain
import CoreUI
import Foundation
import SharedKit

/// The desktop integrations of lib/core/platform/**: tray item + close-to-tray, window placement, custom app icon / name,
/// and the "user came back" counter. In demo mode only the counter runs (no tray item, no saved window frame).
@MainActor
final class PlatformServices {
    let isDemo: Bool
    let lifecycle = CloseToTrayLifecycle()
    let placement = WindowPlacementRecorder()
    let iconService: AppIconService
    let nameService: AppNameService
    let resume = AppResumeCounter()
    private var attachedWindow: NSWindow?

    init(isDemo: Bool) {
        self.isDemo = isDemo
        let life = lifecycle
        iconService = AppIconService(onApply: { image in life.setTrayIcon(image) })
        nameService = AppNameService(setTrayToolTip: { name in life.setTrayToolTip(name) })
    }

    func start(shell: ShellModel) {
        iconService.reapply()
        nameService.apply()
        // Coming back to the app refreshes the ticket open in the detail panel (merged / closed elsewhere meanwhile).
        observeChanges({ [resume] in resume.count }) { _ in
            guard let id = shell.nav.openTicketId, let ticket = shell.detail.tickets[id] else { return }
            Task { _ = await shell.services.ticketDetail.refresh(ticket: ticket) }
        }
        // The tray menu follows the language picker (it is a native menu: nothing rebuilds it by itself).
        observeChanges({ shell.settings.localeCode }) { [lifecycle] code in
            AppLanguage.apply(code)
            lifecycle.updateStrings(Self.trayStrings)
        }
    }

    /// The tray menu's labels in the language in use.
    static var trayStrings: StatusItemStrings {
        StatusItemStrings(openApp: appString("trayOpenApp", "Open WorkNexus"), quitApp: appString("trayQuitApp", "Quit WorkNexus"))
    }

    /// Called once the window exists: restores and records its frame and installs the tray item.
    func attach(window: NSWindow) {
        guard !isDemo, attachedWindow !== window else { return }
        attachedWindow = window
        placement.attach(to: window)
        lifecycle.initialize(window: window, strings: Self.trayStrings)
        nameService.apply()
    }

    /// A Dock click while the window is hidden (closed to the tray): brings that window back. False when this app has no
    /// hidden window to bring (demo runs, before the window attached), so the system's own reopen goes ahead.
    func reopenWindow() -> Bool {
        guard let window = attachedWindow else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        lifecycle.open()
        return true
    }
}
