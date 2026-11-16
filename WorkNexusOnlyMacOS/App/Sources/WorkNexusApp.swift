import AppKit
import CoreDomain
import CoreTools
import CoreUI
import FeatureConnections
import SharedKit
import SwiftUI

@main
struct WorkNexusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var root: CompositionRoot? = try? CompositionRoot()

    var body: some Scene {
        // A single window: a Dock click or File > New must never open a second one (Window, not WindowGroup).
        Window(AppIdentity.appName, id: "main") {
            Group {
                if let root {
                    RootView(root: root).onAppear { appDelegate.attach(root) }
                } else {
                    Text("Could not open the database.").padding()
                }
            }
            .frame(minWidth: 680, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { AppCommands(root: root) }
    }
}

/// The window's content: theme and language from the settings, the environment every feature reads, the connect and
/// workspace dialogs, and the app-lifetime start-up of `CompositionRoot`.
private struct RootView: View {
    let root: CompositionRoot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var shell = root.shell
        // Picking a language acts at once: the strings, the locale, and a rebuilt shell (`.id`) all follow the setting.
        let _ = AppLanguage.apply(shell.settings.localeCode)
        let theme = shell.theme(systemIsDark: scheme == .dark)
        let content = AppShell(model: shell).id(AppLanguage.current)
        root.connections.connectDialog(
            isPresented: $shell.connectRequested,
            over: root.connections.workspaceDialogs(creating: $shell.createWorkspaceRequested, editing: $shell.editWorkspaceRequested,
                                                    onCreated: { shell.workspaceCreated($0) }, over: content))
            .rootEnvironment(root, theme: theme)
            .environment(\.locale, AppLanguage.locale)
            .appDialog(isPresented: $shell.customAccentRequested) {
                CustomColorDialog(initial: shell.settings.accentColorValue ?? Int(AppPalette.accentPresets[0]),
                                  onPick: { v in shell.updateSettings { $0.accentColorValue = v } },
                                  onClose: { shell.customAccentRequested = false })
            }
            .preferredColorScheme(shell.settings.themeFollowsSystem ? nil : theme.colorScheme)
            .background(WindowConfigurator { root.platform.attach(window: $0) })
            .task { await root.start() }
            // One source of truth: the shell's selection drives which mini app page is on screen (and clears it when a
            // rail section, account or settings is picked).
            .onChange(of: shell.nav.state.miniAppId, initial: true) { _, id in root.miniApps.model.show(id) }
    }
}

/// Hands the app's lifecycle events the shell needs: a Dock click on a hidden window brings it back instead of opening a
/// second one (the window hides to the tray when closed).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var root: CompositionRoot?

    @MainActor func attach(_ root: CompositionRoot) { self.root = root }

    @MainActor func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let root, root.platform.reopenWindow() else { return true }
        return false
    }

    /// Quitting waits a moment for the mini apps' session cookies to be copied into the keychain (WebKit forgets them when
    /// the app quits): the copy is asynchronous, so the answer is "later". Never longer than `quitGrace`.
    @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let root, !root.isDemo else { return .terminateNow }
        var replied = false
        let reply = { @MainActor in
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in await root.miniApps.stopSessionCookies(); reply() }
        Task { @MainActor in try? await Task.sleep(for: Self.quitGrace); reply() }
        return .terminateLater
    }

    private static let quitGrace: Duration = .milliseconds(1500)
}

/// Menu-bar commands (Settings…, search, refresh, new bug/task) so the app behaves like a Mac app, not a web view. ⌘K and ⌘R
/// go to the board on screen first (`\.boardSearch` / `\.boardRefresh` focused values) and only then to the global action,
/// so the menu no longer shadows the boards' own shortcuts.
private struct AppCommands: Commands {
    let root: CompositionRoot?
    @FocusedValue(\.boardSearch) private var boardSearch
    @FocusedValue(\.boardRefresh) private var boardRefresh

    private var accountId: String? {
        if case .account(let id)? = root?.shell.nav.state.rail { return id }
        return nil
    }

    var body: some Commands {
        // Read so the menu is rebuilt (and re-titled) when the language changes.
        let _ = root?.shell.settings.localeCode
        CommandGroup(replacing: .appSettings) {
            Button(appString("settings", "Settings") + "…") { root?.shell.nav.select(.settings) }.keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            // Opens the rail's "+" menu (a bug and a task per ZenTao account, filed into the open scope).
            Button(appString("newBugOrTask", "New bug or task…")) { root?.shell.newTicketMenuTick += 1 }
                .keyboardShortcut("n", modifiers: .command)
                .disabled((root?.shell.host.newTicketTargets?() ?? []).isEmpty)
        }
        CommandGroup(after: .toolbar) {
            Button(appString("searchTickets", "Search")) {
                if let boardSearch { boardSearch() } else { root?.shell.searchFocusTick += 1 }
            }
            .keyboardShortcut("k", modifiers: .command)
            Button(appString("refresh", "Refresh")) {
                if let boardRefresh { boardRefresh() }
                else if let id = accountId, let sync = root?.shell.services.sync { Task { _ = await sync.sync(accountId: id) } }
            }
            .keyboardShortcut("r", modifiers: .command).disabled(boardRefresh == nil && accountId == nil)
        }
    }
}
