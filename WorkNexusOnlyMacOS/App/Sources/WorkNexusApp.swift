import AppKit
import CoreDomain
import CoreTools
import CoreUI
import FeatureChat
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
                    Text(verbatim: "Could not open the database.").padding()
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
            // "Show FPS" (Settings › Local data › Diagnostics): a badge in the window's bottom corner, over everything (the
            // title bar is full of breadcrumbs and search at narrow widths). It takes no clicks.
            .overlay(alignment: .bottomTrailing) { FpsBadge().environment(\.appTheme, theme).padding(theme.spacing.s6) }
            .preferredColorScheme(shell.settings.themeFollowsSystem ? nil : theme.colorScheme)
            .background(WindowConfigurator { root.platform.attach(window: $0) })
            .task { root.start() }
            // One source of truth: the shell's selection drives which mini app page is on screen (and clears it when a
            // rail section, account or settings is picked).
            .onChange(of: shell.nav.state.miniAppId, initial: true) { _, id in root.miniApps.model.show(id) }
            // A second click on Chat in the rail folds the conversation list away (and brings it back): the rail's "chat"
            // pane and the chat's own list are one switch. The chat remembers it across launches, so it leads at start.
            .onAppear { shell.nav.setPane("chat", collapsed: ChatPanelVisibility.shared.listHidden) }
            .onChange(of: shell.nav.isPaneCollapsed("chat")) { _, folded in ChatPanelVisibility.shared.listHidden = folded }
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
        // A run-loop timer, not a task: while the app waits for this answer, a quit asked from main-queue work leaves the
        // main queue blocked, and a timer still fires there. Without it the app hung in "quitting" for good (the update
        // never installed).
        let grace = Timer(timeInterval: Self.quitGrace, repeats: false) { _ in MainActor.assumeIsolated { reply() } }
        RunLoop.main.add(grace, forMode: .common)
        return .terminateLater
    }

    private static let quitGrace: TimeInterval = 1.5
}

/// Starting the app again: a detached shell waits for this process to end, then opens the app bundle again.
enum AppRelaunch {
    @MainActor static func now() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundle = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open '\(bundle)'"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { Diagnostics.warning("app", "Could not restart: \(error.localizedDescription)"); return }
        AppQuit.now()
    }
}

/// Quitting the app from code.
enum AppQuit {
    /// Asks the app to quit from a run-loop timer: called from main-queue work (a task, a dispatched block), a direct
    /// `NSApp.terminate` would wait inside that work for answers queued behind it, and never quit.
    @MainActor static func now() {
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }
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
            Divider()
            // The chat's privacy mode, from anywhere in the app: at hand the moment a screen is shared.
            Toggle(appString("chatPrivacyMode", "Privacy mode"), isOn: Binding(
                get: { root?.shell.settings.chatPrivacy.enabled ?? false },
                set: { on in root?.shell.updateSettings { $0.chatPrivacy.enabled = on } }))
                .keyboardShortcut(ChatPrivacyShortcut.key, modifiers: ChatPrivacyShortcut.modifiers)
                .disabled(root == nil)
        }
    }
}
