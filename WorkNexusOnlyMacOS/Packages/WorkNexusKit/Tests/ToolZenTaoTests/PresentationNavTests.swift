import AppKit
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI
import XCTest
@testable import ToolZenTao

/// The ZenTao nav pane's decisions (pin toggling, pane rows and their order, the module tree's counts, what the
/// product / execution pickers offer for a search and a tab) and an off-screen render of its views.
@MainActor
final class PresentationNavTests: XCTestCase {
    // MARK: Fixtures

    private let account = Account(id: "zt1", workspaceId: "w1", providerType: .zentao, handle: "thanh")

    private func product(_ id: String, _ name: String) -> ProviderProduct { ProviderProduct(id: id, name: name, accountId: "zt1") }
    private func project(_ id: String, _ name: String, program: String? = nil) -> ProviderProject {
        ProviderProject(id: id, name: name, accountId: "zt1", programId: program.map { _ in "pg" }, programName: program)
    }
    private func execution(_ id: String, _ name: String, project: String = "p1", account: String = "zt1") -> ProviderExecution {
        ProviderExecution(id: id, name: name, projectId: project, accountId: account)
    }

    private func navTicket(_ id: String, status: UnifiedStatus = .todo, providerStatus: String = "active", assignee: String? = nil,
                           type: String, entity: TicketProviderEntity) -> Ticket {
        Ticket(id: id, accountId: "zt1", projectId: "p", providerType: .zentao, externalKey: id, title: "T\(id)", body: "",
               priority: .medium, status: status, providerStatus: providerStatus, sourceHash: "h", externalType: type,
               assignee: assignee, providerEntity: entity)
    }
    private func bug(_ id: String, product: String, module: String? = nil, status: UnifiedStatus = .todo, providerStatus: String = "active",
                     assignee: String? = nil) -> Ticket {
        navTicket(id, status: status, providerStatus: providerStatus, assignee: assignee, type: "Bug",
                  entity: .zentaoBug(ZenTaoBugEntity(product: product, module: module)))
    }
    private func task(_ id: String, project: String, module: String? = nil, status: UnifiedStatus = .todo, assignee: String? = nil) -> Ticket {
        navTicket(id, status: status, assignee: assignee, type: "Task", entity: .zentaoTask(ZenTaoTaskEntity(project: project, module: module)))
    }
    private func query(_ tickets: [Ticket], modules: Set<String> = []) -> BoardQuery {
        var f = FilterState(); f.modules = modules
        return BoardQuery(tickets: tickets, filter: f, accountWorkspace: ["zt1": "w1"], now: Date())
    }

    // MARK: Pins

    func testToggledAppendsAMissingKeyAndRemovesAPresentOne() {
        XCTAssertEqual(ZentaoNavLogic.toggled(["zt1:1"], "zt1:2"), ["zt1:1", "zt1:2"])
        XCTAssertEqual(ZentaoNavLogic.toggled(["zt1:1", "zt1:2", "zt1:3"], "zt1:2"), ["zt1:1", "zt1:3"])
        XCTAssertEqual(ZentaoNavLogic.toggled([], "zt1:9"), ["zt1:9"])
    }

    func testPinKeysAreAccountScoped() {
        XCTAssertEqual(ZentaoNavLogic.productKey(accountId: "zt1", productId: "7"), "zt1:7")
        XCTAssertEqual(ZentaoNavLogic.executionKey(accountId: "zt2", executionId: "7"), "zt2:7")
        XCTAssertEqual(ZentaoNavLogic.pinnedExecutionIds(["zt1:7", "zt2:8", "zt1:9"], accountId: "zt1"), ["7", "9"])
        XCTAssertEqual(ZentaoNavLogic.pinnedExecutionIds(["zt1:7"], accountId: "zt"), [], "a prefix of the id is not the account")
    }

    // MARK: Pane rows

    func testBugPaneListsTheOpenUnpinnedProductAboveThePinnedOnesInProductOrder() {
        let all = [product("1", "Alpha"), product("2", "Beta"), product("3", "Gamma"), product("4", "Delta")]
        let rows = ZentaoNavLogic.productRows(products: all, pinned: ["zt1:3", "zt1:1", "zt2:4"], accountId: "zt1", openId: "2")
        // Beta is open but not pinned: first. The pinned follow in the account's product order (not the pin order);
        // Delta is pinned for another account.
        XCTAssertEqual(rows.map(\.name), ["Beta", "Alpha", "Gamma"])
    }

    func testBugPaneDoesNotRepeatAnOpenPinnedProduct() {
        let all = [product("1", "Alpha"), product("2", "Beta")]
        XCTAssertEqual(ZentaoNavLogic.productRows(products: all, pinned: ["zt1:2"], accountId: "zt1", openId: "2").map(\.name), ["Beta"])
        XCTAssertEqual(ZentaoNavLogic.productRows(products: all, pinned: [], accountId: "zt1", openId: nil).map(\.name), [])
    }

    func testTaskPaneKeepsPinOrderAndResolvesPinsAgainstLoadedExecutions() {
        let known = [execution("10", "Sprint 10"), execution("11", "Sprint 11"), execution("12", "Sprint 12"),
                     execution("12", "Other server", account: "zt2")]
        let rows = ZentaoNavLogic.executionRows(open: execution("11", "Sprint 11"), pinned: ["zt1:12", "zt2:10", "zt1:10", "zt1:12", "zt1:99"],
                                                known: known, accountId: "zt1")
        // 11 is open and unpinned: first. Pins keep the order they were made in; a duplicate shows once, another
        // account's pin is not listed, and a pin whose execution is not loaded (99) is left out.
        XCTAssertEqual(rows.map(\.id), ["11", "12", "10"])
        XCTAssertEqual(rows.map(\.name), ["Sprint 11", "Sprint 12", "Sprint 10"])
    }

    func testTaskPaneListsTheOpenExecutionOnceWhenItIsPinned() {
        let open = execution("10", "Sprint 10")
        let rows = ZentaoNavLogic.executionRows(open: open, pinned: ["zt1:10"], known: [open], accountId: "zt1")
        XCTAssertEqual(rows.map(\.id), ["10"])
        XCTAssertEqual(ZentaoNavLogic.executionRows(open: open, pinned: [], known: [], accountId: "zt1").map(\.id), ["10"])
    }

    // MARK: Module tree

    func testModuleScopeKeyFollowsTheBoardOnScreen() {
        let p = ZentaoProductSelection(accountId: "zt1", productId: "5", productName: "P")
        let e = ZentaoExecutionSelection(accountId: "zt1", projectId: "2", executionId: "9", executionName: "E")
        XCTAssertEqual(ZentaoNavLogic.moduleScopeKey(bugs: true, product: p, execution: e), "b:zt1:5")
        XCTAssertEqual(ZentaoNavLogic.moduleScopeKey(bugs: false, product: p, execution: e), "t:zt1:9")
        XCTAssertEqual(ZentaoNavLogic.moduleScopeKey(bugs: true, product: nil, execution: e), "none")
        XCTAssertEqual(ZentaoNavLogic.moduleScopeKey(bugs: false, product: p, execution: nil), "none")
    }

    private let paths = [ZentaoModulePath(id: "0", path: "/"), ZentaoModulePath(id: "1", path: "Live"),
                         ZentaoModulePath(id: "2", path: "Live/Share"), ZentaoModulePath(id: "3", path: "Chat")]

    func testBugModuleTreeCountsTheBoardsBugsAndSkipsClosedOnTheUnclosedTab() {
        let tickets = [bug("1", product: "5", module: "2"), bug("2", product: "5", module: "2"), bug("3", product: "5", module: "3"),
                       bug("4", product: "5", module: "3", status: .done, providerStatus: "closed")]
        let unclosed = ZentaoNavLogic.moduleTree(bugs: true, query: query(tickets), bugTab: .unclosed, leader: ZenTaoLeaderFilter(),
                                                 paths: paths, hideEmpty: false)
        XCTAssertEqual(unclosed.total, 3)
        XCTAssertEqual(unclosed.nodes.map(\.name), ["Live", "Share", "Chat"], "ZenTao's 'no module' is not listed")
        XCTAssertEqual(unclosed.nodes.map(\.depth), [0, 1, 0])
        XCTAssertEqual(unclosed.nodes.map(\.count), [0, 2, 1])
        let all = ZentaoNavLogic.moduleTree(bugs: true, query: query(tickets), bugTab: .all, leader: ZenTaoLeaderFilter(), paths: paths, hideEmpty: false)
        XCTAssertEqual(all.total, 4)
        XCTAssertEqual(all.nodes.map(\.count), [0, 2, 2])
    }

    func testModuleTreeIgnoresThePickedModuleSoSiblingsKeepTheirCounts() {
        let tickets = [bug("1", product: "5", module: "2"), bug("2", product: "5", module: "3")]
        let tree = ZentaoNavLogic.moduleTree(bugs: true, query: query(tickets, modules: ["2"]), bugTab: .unclosed, leader: ZenTaoLeaderFilter(),
                                             paths: paths, hideEmpty: false)
        XCTAssertEqual(tree.total, 2)
        XCTAssertEqual(tree.nodes.map(\.count), [0, 1, 1])
    }

    func testHideEmptyKeepsAParentOfABusyModuleAndThePickedOne() {
        let tickets = [bug("1", product: "5", module: "2")]
        let hidden = ZentaoNavLogic.moduleTree(bugs: true, query: query(tickets), bugTab: .unclosed, leader: ZenTaoLeaderFilter(), paths: paths, hideEmpty: true)
        XCTAssertEqual(hidden.nodes.map(\.name), ["Live", "Share"], "Live holds nothing itself but its sub-module is busy; Chat is empty")
        let picked = ZentaoNavLogic.moduleTree(bugs: true, query: query(tickets, modules: ["3"]), bugTab: .unclosed, leader: ZenTaoLeaderFilter(),
                                               paths: paths, hideEmpty: true)
        XCTAssertEqual(picked.nodes.map(\.name), ["Live", "Share", "Chat"], "the picked module never vanishes from under the cursor")
    }

    func testTaskModuleTreeCountsTasksNotBugs() {
        let tickets = [task("1", project: "p1", module: "3"), task("2", project: "p1", module: "3"), bug("3", product: "5", module: "3")]
        let tree = ZentaoNavLogic.moduleTree(bugs: false, query: query(tickets), bugTab: .unclosed, leader: ZenTaoLeaderFilter(), paths: paths, hideEmpty: false)
        XCTAssertEqual(tree.total, 2)
        XCTAssertEqual(tree.nodes.last?.count, 2)
    }

    // MARK: Pickers

    func testProductPickerSplitsMineFromOthersAndOrdersByOpenBugsThenName() {
        let products = [product("1", "Zulu"), product("2", "alpha"), product("3", "Bravo"), product("4", "Quiet")]
        let tickets = [bug("a", product: "1", assignee: "thanh"), bug("b", product: "1"), bug("c", product: "2", assignee: "thanh"),
                       bug("d", product: "3"), bug("e", product: "3"), bug("f", product: "3"),
                       bug("g", product: "4", status: .done, assignee: "thanh")]
        func names(_ tab: ZentaoPickerTab, search: String = "") -> [String] {
            ZentaoNavLogic.productChoices(products: products, tickets: tickets, account: account, accountId: "zt1", search: search, tab: tab)
                .map(\.product.name)
        }
        // Mine: products with bugs assigned to the user (a done one still counts as having work there). Zulu has 2
        // open bugs, alpha 1, Quiet 0.
        XCTAssertEqual(names(.mine), ["Zulu", "alpha", "Quiet"])
        XCTAssertEqual(names(.others), ["Bravo"])
        XCTAssertEqual(names(.mine, search: "  ALP "), ["alpha"], "the search is trimmed and case-insensitive")
        let counts = ZentaoNavLogic.productChoices(products: products, tickets: tickets, account: account, accountId: "zt1", search: "", tab: .mine)
        XCTAssertEqual(counts.map(\.openCount), [2, 1, 0], "a done bug is not open")
    }

    func testProductPickerHasNoMineWithoutAnAccount() {
        let tickets = [bug("a", product: "1", assignee: "thanh")]
        let rows = ZentaoNavLogic.productChoices(products: [product("1", "One")], tickets: tickets, account: nil, accountId: "zt1",
                                                 search: "", tab: .others)
        XCTAssertEqual(rows.map(\.product.name), ["One"])
    }

    func testProjectPickerMatchesNameOrProgramAndCountsOpenTasks() {
        let projects = [project("1", "Mobile", program: "Platform"), project("2", "Website"), project("3", "Backend", program: "Platform")]
        let tickets = [task("a", project: "1", assignee: "thanh"), task("b", project: "1"), task("c", project: "1", status: .done),
                       task("d", project: "2"), task("e", project: "3", status: .done, assignee: "Thanh")]
        func choices(_ tab: ZentaoPickerTab, search: String = "") -> [ZentaoProjectChoice] {
            ZentaoNavLogic.projectChoices(projects: projects, tickets: tickets, account: account, accountId: "zt1", search: search, tab: tab)
        }
        XCTAssertEqual(choices(.mine).map(\.project.name), ["Mobile", "Backend"])
        XCTAssertEqual(choices(.mine).map(\.openCount), [2, 0])
        XCTAssertEqual(choices(.others).map(\.project.name), ["Website"])
        XCTAssertEqual(choices(.mine, search: "platform").map(\.project.name), ["Mobile", "Backend"], "the program name matches too")
        XCTAssertEqual(choices(.others, search: "platform").map(\.project.name), [])
    }

    func testTaskInProjectOnlyMatchesTasksOfThatProject() {
        XCTAssertTrue(ZentaoNavLogic.isTask(task("a", project: "1"), inProject: "1"))
        XCTAssertFalse(ZentaoNavLogic.isTask(task("a", project: "1"), inProject: "2"))
        XCTAssertFalse(ZentaoNavLogic.isTask(bug("b", product: "1"), inProject: "1"))
    }

    func testZentaoAccountsKeepOnlyZenTaoInRailOrder() {
        let gh = Account(id: "gh1", workspaceId: "w1", providerType: .github, handle: "octo")
        let b = Account(id: "zt2", workspaceId: "w1", providerType: .zentao, handle: "b")
        let a = Account(id: "zt1", workspaceId: "w1", providerType: .zentao, handle: "a")
        XCTAssertEqual(ZentaoAccountSwitcher.zentaoAccounts([gh, b, a]).map(\.id), ["zt1", "zt2"])
    }

    // MARK: Render

    /// The module tree with its heading's buttons, and the line a new module is typed on.
    func testTheModuleTreeRendersWithItsAddRow() throws {
        let env = BoardsEnv(section: ZentaoSection.tasks)
        env.state.openExecution(env.execution("e1"))
        env.state.moduleNames["t:zt1:e1"] = .loaded([ZentaoModulePath(id: "3", path: "Chat"), ZentaoModulePath(id: "4", path: "Chat/Share"),
                                                     ZentaoModulePath(id: "5", path: "Speech To Text")])
        let tree = VStack(alignment: .leading, spacing: 0) {
            ZentaoModuleTreeSection(state: env.state, bugs: false)
            ZentaoModuleAddRow(state: env.state, bugs: false, parentId: nil, depth: 0) {}
            ZentaoModuleAddRow(state: env.state, bugs: false, parentId: "3", depth: 1) {}
        }
        .padding(8).frame(maxHeight: .infinity, alignment: .top)
        try render("module-tree", tree, size: CGSize(width: 300, height: 380))
        try render("module-tree-dark", tree, size: CGSize(width: 300, height: 380), dark: true)
    }

    private let outDir = URL(fileURLWithPath: "/tmp/wn-zt-nav-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.panel).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private struct PickerHarness: View {
        @State var search = ""
        @State var tab = ZentaoPickerTab.mine
        let choices: [ZentaoProductChoice]
        var body: some View {
            ZentaoPickerShell(searchHint: "Filter products", search: $search, tab: $tab) {
                ZentaoProductPopoverList(choices: choices, selectedId: "2") { _ in }
            }
        }
    }

    func testProductPickerRenders() throws {
        let choices = [ZentaoProductChoice(product: product("1", "Livestream"), openCount: 12),
                       ZentaoProductChoice(product: product("2", "Mobile app with a rather long product name"), openCount: 3),
                       ZentaoProductChoice(product: product("3", "Quiet"), openCount: 0)]
        try render("product-picker", PickerHarness(choices: choices), size: CGSize(width: 340, height: 400))
        try render("product-picker-dark", PickerHarness(choices: choices), size: CGSize(width: 340, height: 400), dark: true)
        try render("product-picker-empty", PickerHarness(choices: []), size: CGSize(width: 340, height: 400))
    }

    func testProjectNodesRenderOpenLoadingAndFailedStates() throws {
        let choice = ZentaoProjectChoice(project: project("1", "Mobile"), openCount: 4)
        let list = ZentaoLoad<[ProviderExecution]>.loaded([execution("10", "Sprint 10"), execution("11", "Sprint 11")])
        let view = VStack(alignment: .leading, spacing: 0) {
            ZentaoProjectNode(choice: choice, openExecutionId: "11", openProjectId: "1", executions: list, onExpand: {}, onSelect: { _ in })
            ZentaoProjectNode(choice: ZentaoProjectChoice(project: project("2", "Loading"), openCount: 0), openExecutionId: nil,
                              openProjectId: "2", executions: .loading, onExpand: {}, onSelect: { _ in })
            ZentaoProjectNode(choice: ZentaoProjectChoice(project: project("3", "Empty"), openCount: 0), openExecutionId: nil,
                              openProjectId: "3", executions: .loaded([]), onExpand: {}, onSelect: { _ in })
            ZentaoProjectNode(choice: ZentaoProjectChoice(project: project("4", "Broken"), openCount: 0), openExecutionId: nil,
                              openProjectId: "4", executions: .failed(.network("boom")), onExpand: {}, onSelect: { _ in })
            ZentaoProjectNode(choice: ZentaoProjectChoice(project: project("5", "Folded"), openCount: 1), openExecutionId: nil,
                              openProjectId: nil, executions: nil, onExpand: {}, onSelect: { _ in })
        }
        .padding(8)
        try render("project-nodes", view, size: CGSize(width: 340, height: 320))
        try render("project-nodes-dark", view, size: CGSize(width: 340, height: 320), dark: true)
    }

    func testSwitcherButtonRenders() throws {
        let view = VStack(alignment: .leading, spacing: 8) {
            ZentaoSwitcherButton(kind: "Project", title: "Sprint 12 - checkout redesign") { _ in Color.clear }
            ZentaoSwitcherButton(kind: "Product", title: "Select Product") { _ in Color.clear }
        }
        .padding(12)
        try render("switcher-buttons", view, size: CGSize(width: 340, height: 90))
    }
}
