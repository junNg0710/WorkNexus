import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI
import XCTest
@testable import ToolZenTao

/// Renders the ZenTao detail views off-screen so layout crashes show up in `swift test` and the PNGs can be eyeballed
/// (`/tmp/wn-zentao-render/detail-*.png`). Asserts only that something non-blank was drawn.
@MainActor
final class PresentationDetailRenderTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-zentao-render")

    func renderPublic<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) async throws { try await render(name, view, size: size, dark: dark) }
    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.bg).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Lets the views' `.task` loads (users, bytes, related bugs) land before the snapshot.
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("detail-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private var task: Ticket {
        var t = detailTicket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(
            parentId: "10", parentName: "Chat feature", subtasks: [TicketSubtask(id: "13", title: "Write tests", status: .todo, assignee: "Cat"),
                                                                    TicketSubtask(id: "14", title: "Ship it", status: .done),
                                                                    TicketSubtask(id: "15", title: "Snapshot tests", status: .inprogress, parentId: "13")],
            execution: "31", estimate: 8, consumed: 5, left: 3, realStarted: Date().addingTimeInterval(-86_400), openedByHandle: "ryan", executionName: "Sprint 12",
            estStarted: "2026-11-01", deadline: "2026-11-30", openedBy: "Ryan", openedDate: Date().addingTimeInterval(-9 * 86_400))))
        t.assignee = "Thanh"; t.title = "Notification layer display"
        return t
    }

    private var bug: Ticket {
        var t = detailTicket("Bug", "active", key: "7", status: .inbox, entity: .zentaoBug(ZenTaoBugEntity(
            product: "4", execution: "31", module: "7", story: "99", task: "12", productName: "Livestream", executionName: "Sprint 12",
            bugType: "codeerror", confirmed: 0, severity: 2, activatedCount: 2,
            openedDate: Date().addingTimeInterval(-3 * 86_400), openedBuild: "trunk", assignedDate: Date().addingTimeInterval(-86_400))))
        t.severity = 2
        return t
    }

    private func png() -> Data {
        let img = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { r in
            NSColor.systemTeal.setFill(); r.fill(); NSColor.white.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 80, dy: 40)).fill(); return true
        }
        return NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    func testActionsBarAndHeaderParts() async throws {
        let env = DetailEnv()
        let view = VStack(alignment: .leading, spacing: 16) {
            ZentaoTicketActions(deps: env.deps, state: env.state, ticket: task)
            ZentaoTicketActions(deps: env.deps, state: env.state, ticket: bug)
            ZentaoParentTaskLink(deps: env.deps, ticket: task, parentId: "10", parentName: "Chat feature")
            HStack(spacing: 12) {
                ZentaoBugStatusStrip(ticket: detailTicket("Bug", "resolved", status: .review), bug: ZenTaoBugEntity(resolution: "fixed"))
                ZentaoPersonChip(accountId: "zt", name: "Thanh")
                ZentaoCopyActionsMenu(ticket: task)
                ZentaoRowQuickCopyButton(ticket: task)
            }
            ZentaoCardParentLine(ticket: task)
        }
        .padding(20)
        try await render("actions", view, size: CGSize(width: 640, height: 280))
        try await render("actions-dark", view, size: CGSize(width: 640, height: 280), dark: true)
    }

    func testDialogs() async throws {
        let env = DetailEnv(members: [ProviderUser(account: "cat", displayName: "Cat"), ProviderUser(account: "ryan", displayName: "Ryan")])
        try await render("dialog-finish", ZentaoTaskActionDialog(deps: env.deps, state: env.state, ticket: task, action: .finish) {}.padding(24),
                   size: CGSize(width: 560, height: 760))
        try await render("dialog-resolve", ZentaoResolveDialog(deps: env.deps, state: env.state, ticket: bug) {}.padding(24), size: CGSize(width: 560, height: 560))
        try await render("dialog-assign-task", ZentaoTaskAssignDialog(deps: env.deps, state: env.state, ticket: task) {}.padding(24), size: CGSize(width: 560, height: 480))
        try await render("dialog-nonfix", ZentaoNonFixResolutionDialog(onPick: { _ in }, onClose: {}).padding(24), size: CGSize(width: 480, height: 240))
        try await render("dialog-finish-dark", ZentaoTaskActionDialog(deps: env.deps, state: env.state, ticket: task, action: .finish) {}.padding(24),
                   size: CGSize(width: 560, height: 760), dark: true)
    }

    func testSidebarsAndBlocks() async throws {
        let env = DetailEnv()
        let b = bug, t = task
        env.store.tickets[b.id] = b
        var related = detailTicket("Bug", "active", key: "21", entity: .zentaoBug(ZenTaoBugEntity(task: "12")))
        related.title = "Notification badge overlaps the avatar"
        env.store.tickets[related.id] = related
        let side = HStack(alignment: .top, spacing: 16) {
            ScrollView { ZentaoBugSections(deps: env.deps, state: env.state, bug: { if case .zentaoBug(let e) = b.providerEntity { e } else { ZenTaoBugEntity() } }(), ticket: b) }.frame(width: 320)
            ScrollView { ZentaoTaskSections(deps: env.deps, state: env.state, task: { if case .zentaoTask(let e) = t.providerEntity { e } else { ZenTaoTaskEntity() } }(), ticket: t) }.frame(width: 320)
        }
        .padding(16)
        try await render("sidebars", side, size: CGSize(width: 720, height: 760))
        let blocks = VStack(alignment: .leading, spacing: 20) {
            ZentaoTaskEffortBar(task: { if case .zentaoTask(let e) = t.providerEntity { e } else { ZenTaoTaskEntity() } }())
            ZentaoSubtaskList(deps: env.deps, ticket: t, subtasks: { if case .zentaoTask(let e) = t.providerEntity { e.subtasks } else { [] } }())
            ZentaoBugAttachments(deps: env.deps, ticket: b, attachments: [
                TicketAttachment(id: "1", title: "repro.mp4", url: "/file-read-1.mp4", extension: "mp4", size: 8_400_000, addedBy: "Ryan"),
                TicketAttachment(id: "2", title: "crash.log", url: "/file-read-2.log", extension: "log", size: 12_000),
                TicketAttachment(id: "3", title: "spec.pdf", url: "/file-read-3.pdf", extension: "pdf", size: 220_000, addedBy: "Cat")])
        }
        .padding(20)
        try await render("blocks", blocks, size: CGSize(width: 560, height: 480))
    }

    func testAttachmentViewerShowsAnImageFromTheAuthenticatedSession() async throws {
        let env = DetailEnv()
        env.adapter.bytes = png()
        let att = TicketAttachment(id: "3", title: "shot.png", url: "/file-read-3.png", extension: "png", size: 40_000)
        let viewer = ZentaoAttachmentViewer(deps: env.deps, ticket: bug, attachment: att) {}
        try await render("viewer-image", viewer, size: CGSize(width: 880, height: 600))
        env.adapter.bytes = Data("# Notes\n\n- one\n- two".utf8)
        let md = TicketAttachment(id: "4", title: "notes.md", url: "/file-read-4.md", extension: "txt")
        try await render("viewer-markdown", ZentaoAttachmentViewer(deps: env.deps, ticket: bug, attachment: md) {}, size: CGSize(width: 880, height: 600))
    }
}

extension PresentationDetailRenderTests {
    func testTaskBugsCardAlone() async throws {
        let env = DetailEnv()
        var related = detailTicket("Bug", "active", key: "21", entity: .zentaoBug(ZenTaoBugEntity(task: "12")))
        related.title = "Notification badge overlaps the avatar"
        env.store.tickets[related.id] = related
        let t = detailTicket("Task", "doing", entity: .zentaoTask(ZenTaoTaskEntity(execution: "31")))
        try await renderPublic("taskbugs", ZentaoTaskSections(deps: env.deps, state: env.state, task: ZenTaoTaskEntity(execution: "31"), ticket: t).padding(16), size: CGSize(width: 360, height: 420))
    }
}
