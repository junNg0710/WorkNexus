import AppKit
import CoreDomain
import CorePersistence
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureMiniApps

/// Renders the Mac app views off-screen (PNGs in /tmp/wn-native-render/native-*.png). The real rail button (`RailLabeledButton`)
/// lives in SharedKit, which this target cannot import, so the rail block here is a stand-in cell of the same 64x54 size around
/// the real `NativeAppRailIcon`; the dialog and the settings list are the real views. Asserts only that something was drawn.
@MainActor
final class NativeAppsRenderTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-native-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false, pad: CGFloat = 0) async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.padding(pad).frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(theme.colors.bg).environment(\.appTheme, theme).environment(\.colorScheme, theme.colorScheme)
            .environment(\.toasts, AppToastController()))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("native-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
        window.contentView = nil
    }

    /// A model over real system apps (their icons), with Safari "running", Notes missing, and nothing launched.
    private func seeded() async throws -> NativeHarness {
        let h = try NativeHarness(installed: InstalledAppsScanner.scan(InstalledAppsScanner.defaultRoots, PlistAppBundleReader()))
        let reader = PlistAppBundleReader()
        let apps = ["Safari", "Notes", "Calendar", "Mail"].compactMap { name -> NativeApp? in
            for folder in ["/System/Applications", "/Applications"] {
                if case .success(let info) = reader.read(path: "\(folder)/\(name).app") {
                    return NativeApp(id: name.lowercased(), name: info.name, bundleId: info.bundleId, path: info.path, position: 0)
                }
            }
            return nil
        }
        XCTAssertGreaterThanOrEqual(apps.count, 2, "the machine has no system apps to draw")
        var placed = apps
        for i in placed.indices { placed[i].position = i }
        placed.append(NativeApp(id: "gone", name: "Slack", bundleId: "com.tinyspeck.slackmacgap", path: "/Applications/Slack.app", position: placed.count))
        h.launcher.running = Set(placed.prefix(1).map(\.bundleId))
        h.launcher.present = Set(placed.dropLast().map(\.path))
        await h.seed(placed)
        return h
    }

    /// The rail's stand-in cell: the real icon over the name in a 64x54 box, as `RailLabeledButton` lays it out.
    private struct RailCell: View {
        @Environment(\.appTheme) private var theme
        let item: NativeAppRailItem; let model: NativeAppsModel
        var body: some View {
            VStack(spacing: theme.spacing.s2) {
                NativeAppRailIcon(icon: model.icon(forPath: item.path), running: item.running, missing: item.missing)
                    .frame(height: theme.sizes.icon24)
                Text(item.name).font(theme.typography.caption).lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, theme.spacing.s2).frame(width: 64, height: 54).foregroundStyle(theme.colors.tx2)
        }
    }

    private struct RailBlock: View {
        @Environment(\.appTheme) private var theme
        let model: NativeAppsModel
        var body: some View {
            VStack(spacing: theme.spacing.s2) {
                ForEach(model.railItems) { RailCell(item: $0, model: model) }
                VStack(spacing: theme.spacing.s2) {
                    Image(systemName: "plus.app").font(.system(size: theme.sizes.icon20)).frame(height: theme.sizes.icon24)
                    Text("Add").font(theme.typography.caption)
                }
                .frame(width: 64, height: 54).foregroundStyle(theme.colors.tx2)
            }
            .padding(theme.spacing.s8).frame(width: 76).background(theme.colors.panel)
        }
    }

    func testRailBlockShowsRunningDotAndADimmedMissingApp() async throws {
        let h = try await seeded()
        XCTAssertEqual(h.model.railItems.filter(\.running).count, 1)
        XCTAssertEqual(h.model.railItems.filter(\.missing).map(\.name), ["Slack"])
        try await render("rail", RailBlock(model: h.model), size: CGSize(width: 100, height: 400), pad: 12)
        try await render("rail-dark", RailBlock(model: h.model), size: CGSize(width: 100, height: 400), dark: true, pad: 12)
    }

    func testAddDialogListsInstalledAppsAndMarksTheAddedOnes() async throws {
        let h = try await seeded()
        // Today's installed list begins with apps that are not added; put the added ones first so the "Added" mark is on the picture.
        let all = InstalledAppsScanner.scan(InstalledAppsScanner.defaultRoots, PlistAppBundleReader())
        let added = h.model.apps.filter { !h.model.missingIds.contains($0.id) }
        let marked = added.compactMap { a in all.first { $0.bundleId == a.bundleId } }
        let shown = try NativeHarness(installed: Array((marked + all.filter { a in !marked.contains(a) }).prefix(12)))
        shown.launcher.present = nil
        await shown.seed(h.model.apps.filter { a in marked.contains { $0.bundleId == a.bundleId } })
        await shown.model.loadInstalled()
        XCTAssertFalse(shown.model.installed.isEmpty)
        XCTAssertEqual(shown.model.installed.filter { shown.model.isAdded($0.bundleId) }.count, marked.count)
        try await render("add-dialog-added", NativeAppPickerDialog(model: shown.model, onClose: {}), size: CGSize(width: 520, height: 640), pad: 24)
        await h.model.loadInstalled()
        XCTAssertFalse(h.model.installed.isEmpty)
        try await render("add-dialog", NativeAppPickerDialog(model: h.model, onClose: {}), size: CGSize(width: 520, height: 640), pad: 24)
        try await render("add-dialog-dark", NativeAppPickerDialog(model: h.model, onClose: {}), size: CGSize(width: 520, height: 640), dark: true, pad: 24)
    }

    func testAddDialogWhileLoadingAndWithNoMatch() async throws {
        let empty = try NativeHarness()
        try await render("add-dialog-empty", NativeAppPickerDialog(model: empty.model, onClose: {}), size: CGSize(width: 520, height: 560), pad: 24)
    }

    func testSettingsListWithAMissingApp() async throws {
        let h = try await seeded()
        try await render("settings-list", NativeAppSettingsList(model: h.model), size: CGSize(width: 640, height: 360), pad: 24)
    }
}
