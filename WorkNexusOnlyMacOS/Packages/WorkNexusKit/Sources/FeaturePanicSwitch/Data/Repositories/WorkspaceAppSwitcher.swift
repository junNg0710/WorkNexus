import AppKit
import CoreDomain
import Foundation

/// Ported from: lib/features/panic_switch/data/repositories/channel_app_switcher.dart + macos/Runner/PanicSwitchChannel.swift
/// `AppSwitcher` over `NSWorkspace` / `NSRunningApplication`: only the public launch, activate and hide calls — no
/// Accessibility permission, no automation.
@MainActor
public final class WorkspaceAppSwitcher: AppSwitcher {
    private let folders: [URL]

    public init(folders: [URL] = WorkspaceAppSwitcher.defaultFolders) { self.folders = folders }

    public nonisolated static var defaultFolders: [URL] {
        ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(fileURLWithPath: $0) }
            + [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    /// Running apps with a Dock icon plus the apps in the usual folders, one entry per bundle id, by name. The folders are
    /// read off the main thread.
    public func listApps() async -> Outcome<[AppRef]> {
        var byId: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier, let name = app.localizedName, id != Bundle.main.bundleIdentifier { byId[id] = name }
        }
        let folders = folders
        let installed = await Task.detached(priority: .userInitiated) { Self.scan(folders) }.value
        for (id, name) in installed where byId[id] == nil { byId[id] = name }
        let apps = byId.map { AppRef(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return .success(apps)
    }

    nonisolated static func scan(_ folders: [URL]) -> [(String, String)] {
        let fm = FileManager.default
        var out: [(String, String)] = []
        for folder in folders {
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in items where url.pathExtension == "app" {
                guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
                let name = fm.displayName(atPath: url.path)
                out.append((id, name.hasSuffix(".app") ? String(name.dropLast(4)) : name))
            }
        }
        return out
    }

    /// Opening through LaunchServices brings a running app forward (with all its windows, unhidden) and starts one that is
    /// not running. Unlike `NSRunningApplication.activate`, macOS 14+ honours it while WorkNexus is itself in the background.
    public func activate(_ app: AppRef) async -> Outcome<Void> {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.id) { running.unhide() }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) else {
            return .failure(.notFound("\(app.name) is not installed"))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .success(())
        } catch {
            return .failure(.unexpected("Could not open \(app.name): \(error.localizedDescription)"))
        }
    }

    public func hide(_ app: AppRef) async -> Outcome<Void> {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.id) { running.hide() }
        return .success(())
    }

    /// macOS hides the whole app (its Dock icon stays).
    public func hideSelf() async -> Outcome<Void> {
        NSApp.hide(nil)
        return .success(())
    }
}
