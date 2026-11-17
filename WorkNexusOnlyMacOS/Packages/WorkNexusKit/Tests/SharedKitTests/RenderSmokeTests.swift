import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI
import XCTest
@testable import SharedKit

/// Renders the shared board / detail views off-screen so layout crashes show up in `swift test` and the PNGs can be
/// eyeballed (`/tmp/wn-shared-render/*.png`). Asserts only that something non-blank was drawn.
@MainActor
final class RenderSmokeTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-shared-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.bg).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private func controller(_ tickets: [Ticket]) -> BoardController {
        let store = FakeStore()
        for t in tickets { store.tickets[t.id] = t }
        store.accounts["ztB"] = Account(id: "ztB", workspaceId: "w1", providerType: .zentao, handle: "thanh")
        let services = AppServices(tickets: store, workspaces: store, comments: store, activity: store, syncStatus: SyncTests.RecordingStatus(),
                                   settings: BoardControllerTests.FakeSettings(), credentials: store, sync: BoardControllerTests.NoopSync(),
                                   ticketDetail: BoardControllerTests.NoopSync(), adapters: FakeRegistry())
        let c = BoardController(services: services, nav: AppNavController { _ in "default" }, registry: ToolRegistry())
        c.start()
        return c
    }

    private var sample: [Ticket] {
        [ztBug("101", providerStatus: "active", severity: 1, assignee: "Thanh", entity: ZenTaoBugEntity(openedBy: "Ryan")),
         makeTicket("g1", account: "ztB", provider: .zentao, key: "7", status: .inprogress, priority: .urgent, title: "A much longer ticket title that should wrap onto a few lines in the card", labels: ["ui", "backend"], assignee: "Cat", type: "Task"),
         makeTicket("g2", account: "ztB", provider: .zentao, key: "8", status: .review, title: "Review me", assignee: nil, type: "Task"),
         makeTicket("g3", account: "ztB", provider: .zentao, key: "9", status: .done, title: "Shipped", assignee: "Luci", type: "Bug")]
    }

    func testKanbanBoard() async throws {
        let c = controller(sample)
        try await Task.sleep(for: .milliseconds(100))
        try render("board-kanban", BoardView(controller: c), size: CGSize(width: 1200, height: 520))
        try render("board-kanban-dark", BoardView(controller: c), size: CGSize(width: 1200, height: 520), dark: true)
        try render("board-skeleton", BoardSkeleton(), size: CGSize(width: 1200, height: 400))
    }

    func testTable() async throws {
        let c = controller(sample)
        try await Task.sleep(for: .milliseconds(100))
        let cols = [TicketTableColumn(id: "id", label: "ID", width: 80, sortField: .id) { AnyView(TableIdCell($0)) },
                    TicketTableColumn(id: "title", label: "Title", sortField: .title) { AnyView(TableTitleCell($0)) },
                    TicketTableColumn(id: "pri", label: "Pri", width: 90, sortField: .priority) { AnyView(TablePriorityCell($0)) },
                    TicketTableColumn(id: "who", label: "Assignee", width: 160, sortField: .assignee) { AnyView(TableAssigneeCell($0)) }]
        try render("table", TicketTable(id: "t", columns: cols, rows: sample, controller: c, sort: .newest, onSort: { _ in }), size: CGSize(width: 900, height: 360))
    }

    func testToolbarAndFilters() async throws {
        let c = controller(sample)
        c.facetScope = .bug
        try await Task.sleep(for: .milliseconds(100))
        c.toggleSeverity(1)
        let modes = [ToolViewMode(id: "board", label: "Board", systemImage: "rectangle.split.3x1"), ToolViewMode(id: "table", label: "Table", systemImage: "tablecells")]
        let toolbar = BoardToolbar(controller: c, scopes: [AppSegmentedTab(label: "All", active: true) {}, AppSegmentedTab(label: "Related", active: false) {}],
                                   modes: modes, viewMode: "board", onViewMode: { _ in }) { BoardRefreshButton(loading: false) {} }
        try render("toolbar-wide", toolbar, size: CGSize(width: 1000, height: 120))
        try render("toolbar-narrow", toolbar, size: CGSize(width: 520, height: 120))
        try render("filter-popover", FilterPopover(controller: c), size: CGSize(width: 440, height: 520))
        try render("empty-state", BoardEmptyState(controller: c), size: CGSize(width: 500, height: 300))
    }

    /// Loading: the toolbar stays at the top and the placeholders fill the board area below it, sweeping together.
    func testLoadingPlaceholdersFillTheBoardFromTheTop() async throws {
        let toolbar = VStack(alignment: .leading, spacing: 8) {
            Text("Product › VN_IM_Chat · Bugs").font(.headline)
            HStack { ForEach(0..<6, id: \.self) { _ in SkeletonBox(width: 110, height: 28, radius: 14) } }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        let board = ZStack { VStack(spacing: 0) { toolbar; BoardSkeleton() }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }
        try await renderAfterFadeIn("loading-board", board, size: CGSize(width: 1200, height: 760))
        try await renderAfterFadeIn("loading-table", VStack(spacing: 0) { toolbar; TableSkeleton() }, size: CGSize(width: 1000, height: 600))
        try await renderAfterFadeIn("loading-rows", AppStateView(.loading), size: CGSize(width: 420, height: 420), dark: true)
    }

    /// Like `render`, but waits with the main queue free, so the placeholders' fade-in (a task) has run.
    private func renderAfterFadeIn<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) async throws {
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.bg).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<15 { try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded() }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(name).png"))
    }

    /// A long comment with a numbered list and nested bullets (as ZenTao writes them) stays inside its own row.
    func testALongListCommentDoesNotSpillOverItsNeighbours() async throws {
        let html = """
        <ol><li>(Phạm vi) Spec chỉ ghi iOS, có làm cho android không. Code đang làm cả Android với cùng hành vi. Trên Android, nút phóng to trên cửa sổ PiP và icon app đều mở V2-02 (không tách được như BR-14/15 của iOS)?<ul><li>Tách BR-14 / BR-15 trên Android: không làm được, vì nút phóng to và icon app khởi phục Activity theo cùng một cách.</li><li>Các hành vi còn lại: Android làm giống iOS được.</li></ul></li><li>(BR-08) Khi bàn phím mở, có bottom sheet/dialog, hoặc mở màn full-screen (xem ảnh) thì mini player ẩn hay vẫn hiện, pause hay vẫn play ?</li><li>(BR-25) Icon PiP có cần hiện khi video đang tải và ở Clear Mode không?</li></ol>
        """
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DetailRegionCard { VStack(alignment: .leading) { DetailSectionTitle("Description"); Text("Above the comments") } }
                DetailRegionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        DetailSectionTitle("Comments & Activity")
                        TimelineItem(isFirst: true, isLast: false) { Circle().fill(.gray) } content: { Text("Thanh-VN-Flutter assigned to Thanh") }
                        TimelineItem(isFirst: false, isLast: false) { Circle().fill(.gray) } content: {
                            VStack(alignment: .leading) { Text("Thanh-VN-Flutter commented"); RichBodyText(html, html: true, fontSize: 13) }
                        }
                        TimelineItem(isFirst: false, isLast: true) { Circle().fill(.gray) } content: { Text("Thanh-VN-Flutter edited") }
                    }
                }
            }.padding(20)
        }
        try await renderAfterFadeIn("long-list-comment", view, size: CGSize(width: 620, height: 900))
    }

    func testDetailPanel() async throws {
        let store = FakeStore()
        let t = makeTicket("d1", account: "ztB", provider: .zentao, key: "101", status: .inprogress, priority: .high, title: "Login crashes on submit",
                           labels: ["ui", "zentao-product:3"], assignee: "Thanh", type: "Bug", entity: .zentaoBug(ZenTaoBugEntity(openedBy: "Ryan")))
        var body = t; body.body = "<p>Steps to reproduce:</p><ol><li>Open the app</li><li>Tap <b>Login</b></li></ol>"
        body.url = "https://zentao.example.com/bug-view-101.html"   // with a link: the header's copy-link and open-in-browser buttons
        store.tickets["d1"] = body
        store.accounts["ztB"] = Account(id: "ztB", workspaceId: "w1", providerType: .zentao, handle: "thanh")
        store.comments["c1"] = Comment(id: "c1", ticketId: "d1", authorName: "Ryan", body: "<p>Reproduced on 2.1</p>", createdAt: Date().addingTimeInterval(-3600))
        store.events["e1"] = ActivityEvent(id: "e1", ticketId: "d1", actor: "Thanh", action: "assigned to Cat", at: Date().addingTimeInterval(-7200))
        let services = AppServices(tickets: store, workspaces: store, comments: store, activity: store, syncStatus: SyncTests.RecordingStatus(),
                                   settings: BoardControllerTests.FakeSettings(), credentials: store, sync: BoardControllerTests.NoopSync(),
                                   ticketDetail: BoardControllerTests.NoopSync(), adapters: FakeRegistry())
        let d = DetailController(services: services, nav: AppNavController { _ in "default" }, registry: ToolRegistry())
        d.start()
        try await Task.sleep(for: .milliseconds(150))
        _ = d.model(for: "d1")
        try await Task.sleep(for: .milliseconds(150))
        try render("detail-twopane", DetailPanel(controller: d, ticketId: "d1") {}, size: CGSize(width: 980, height: 700))
        try render("detail-twopane-dark", DetailPanel(controller: d, ticketId: "d1") {}, size: CGSize(width: 980, height: 700), dark: true)
    }

    func testShellPaneAndMisc() throws {
        let rows: [AnyView] = [AnyView(ScopeQuickRow(label: "Assigned to me", systemImage: "person", count: 4, selected: true) {}),
                               AnyView(ScopeEntryRow(name: "Project Alpha", path: "group/alpha", count: 3, isPinned: true, onPinToggle: {}) {}),
                               AnyView(ScopeEntryRow(name: "Beta", color: .orange) {}),
                               AnyView(SidebarGroupToggle(label: "Bugs", expanded: true, count: 5) {}),
                               AnyView(SidebarStatusRow(label: "Loading…", loading: true)), AnyView(SidebarStatusRow(label: "Failed", isError: true) {})]
        try render("shell-pane", ScopeListBody(quickScopeRows: [rows[0]], pinnedRows: [rows[1]], allRows: Array(rows[2...])).frame(width: 300), size: CGSize(width: 300, height: 360))
    }
}
