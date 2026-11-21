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
            lifecycle.setTrayToggle(Self.petToggle(shell))
        }
        // "Show the pet" / "Hide the pet" in the tray menu, following the setting (also when it changes in Settings).
        lifecycle.setTrayToggle(Self.petToggle(shell))
        observeChanges({ shell.settings.showPet }) { [lifecycle] _ in lifecycle.setTrayToggle(Self.petToggle(shell)) }
    }

    /// The tray item that shows or hides the pet, wherever it stands (in the window or on the desktop).
    static func petToggle(_ shell: ShellModel) -> StatusItemToggle {
        let shown = shell.settings.showPet
        return StatusItemToggle(title: shown ? appString("petHide", "Hide the pet") : appString("showPet", "Show the pet"),
                                systemImage: "pawprint") { shell.updateSettings { $0.showPet.toggle() } }
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
    /// The app's window is on screen (not closed to the tray, not in the Dock).
    var windowIsShown: Bool { attachedWindow.map { $0.isVisible && !$0.isMiniaturized } ?? false }

    func reopenWindow() -> Bool {
        guard let window = attachedWindow else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        lifecycle.open()
        return true
    }
}
