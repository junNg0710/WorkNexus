import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureWorkspaceOverview

/// Renders the overview pages off-screen (PNGs in /tmp/wn-feat-render/overview-*.png) so layout problems show up;
/// asserts only that something non-blank was drawn.
@MainActor
final class RenderSmokeTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-feat-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(theme.colors.bg).environment(\.appTheme, theme).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("overview-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: Date())! }

    private func repo(connected: Bool = true) -> FakeOverview {
        let r = FakeOverview()
        r.workspaces = [Workspace(id: "w1", name: "Company A", shortCode: "CA", colorValue: 0xFF3B82F6)]
        guard connected else { return r }
        r.accounts = [Account(id: "zt", workspaceId: "w1", providerType: .zentao, handle: "thanh", baseUrl: "https://zentao.example.com/"),
                      Account(id: "gh", workspaceId: "w1", providerType: .github, handle: "octocat")]
        func bug(_ key: String, _ title: String, _ status: UnifiedStatus, _ raw: String, _ p: Priority, sev: Int, due: Int?, reopened: Int? = nil) -> Ticket {
            makeTicket("zt:b\(key)", accountId: "zt", key: key, type: "Bug", title: title, assignee: "thanh", status: status, raw: raw, priority: p,
                       updatedAt: day(-Int(key)! % 5),
                       entity: .zentaoBug(ZenTaoBugEntity(executionName: "Sprint 24.10", severity: sev, activatedCount: reopened,
                                                          deadline: due.map { ISO8601DateFormatter().string(from: day($0)).prefix(10).description })))
        }
        func task(_ key: String, _ title: String, _ status: UnifiedStatus, _ raw: String, _ p: Priority, subtasks: Int = 0, parent: String? = nil) -> Ticket {
            makeTicket("zt:t\(key)", accountId: "zt", key: key, type: "Task", title: title, assignee: "thanh", status: status, raw: raw, priority: p,
                       updatedAt: day(-Int(key)! % 4),
                       entity: .zentaoTask(ZenTaoTaskEntity(parentName: parent,
                                                            subtasks: (0..<subtasks).map { TicketSubtask(id: "s\($0)", title: "Sub \($0)", status: .todo) })))
        }
        r.tickets = [
            task("231", "Port the overview feature to SwiftUI", .inprogress, "doing", .urgent, subtasks: 3),
            task("230", "Review the tool card spacing against the design", .inprogress, "doing", .medium, parent: "Design polish"),
            task("225", "Write the migration notes", .todo, "wait", .low),
            task("224", "Sync assigned work on launch", .todo, "wait", .high),
            task("201", "Release checklist", .done, "done", .medium),
            bug("88", "Dashboard flickers when the refresh button is pressed twice", .todo, "active", .urgent, sev: 1, due: -2),
            bug("87", "Execution progress shows 100% for an empty sprint", .inbox, "active", .medium, sev: 3, due: 3, reopened: 2),
            bug("86", "Activity row opens the wrong ticket for stories", .todo, "active", .high, sev: 2, due: nil),
            makeTicket("gh:pr1", accountId: "gh", provider: .github, key: "42", type: "PullRequest", title: "Add dark-mode tokens", assignee: nil,
                       status: .review, raw: "open", updatedAt: day(0), entity: .githubItem(GitHubItemEntity(reviewerLogins: ["octocat"]))),
        ]
        var d = ZenTaoDashboard(accountId: "zt", profile: ZenTaoDashboardProfile(account: "thanh", realname: "Thanh"), fetchedAt: Date().addingTimeInterval(-300))
        d.executions = [ZenTaoDashboardExecution(id: "1", name: "Sprint 24.10", projectName: "WorkNexus", status: "doing", progress: 64, end: day(6)),
                        ZenTaoDashboardExecution(id: "2", name: "Hardening", projectName: "Hardening", status: "doing", progress: 100, end: day(-1)),
                        ZenTaoDashboardExecution(id: "3", name: "Backlog grooming", projectName: "WorkNexus", status: "wait", progress: 0, end: day(20))]
        d.executionTotal = 3
        d.activities = [ZenTaoDashboardActivity(id: "a1", actor: "Linh", action: "resolved", objectType: "bug", objectId: "88", objectName: "Dashboard flickers on double refresh", date: Date().addingTimeInterval(-600)),
                        ZenTaoDashboardActivity(id: "a2", actor: "You", action: "started", objectType: "task", objectId: "231", objectName: "Port the overview feature", date: Date().addingTimeInterval(-7200)),
                        ZenTaoDashboardActivity(id: "a3", actor: "Minh", action: "commented on", objectType: "story", objectId: "12", objectName: nil, date: day(-2))]
        d.todos = [ZenTaoDashboardWorkItem(kind: .todo, id: "1", title: "Prepare the sprint demo", status: "wait", priority: 2, deadline: day(1)),
                   ZenTaoDashboardWorkItem(kind: .todo, id: "2", title: "Reply to design feedback", status: "doing", priority: 3)]
        d.todoTotal = 2
        r.dashboards["zt"] = d
        return r
    }

    private func page(_ r: FakeOverview, section: String? = nil, work: MyWorkTarget? = nil) async throws -> OverviewModel {
        let m = makeModel(r)
        m.start()
        try await Task.sleep(for: .milliseconds(150))
        if let section { m.nav.setWorkspaceSection(section) }
        m.myWorkTarget = work
        return m
    }

    func testOverviewPage() async throws {
        let m = try await page(repo())
        try render("overview", WorkspaceOverviewHost(model: m), size: CGSize(width: 1100, height: 1500))
        try render("overview-dark", WorkspaceOverviewHost(model: m), size: CGSize(width: 1100, height: 1500), dark: true)
        try render("overview-narrow", WorkspaceOverviewHost(model: m), size: CGSize(width: 620, height: 1700))
    }

    func testEmptyOverview() async throws {
        let m = try await page(repo(connected: false))
        try render("empty", WorkspaceOverviewHost(model: m), size: CGSize(width: 800, height: 520))
    }

    func testFullWorkLists() async throws {
        let r = repo()
        let account = r.accounts[0]
        let wide = try await page(r, work: MyWorkTarget(account: account, kind: .task))
        try render("work-wide", WorkspaceOverviewHost(model: wide), size: CGSize(width: 1300, height: 820))
        try render("work-wide-dark", WorkspaceOverviewHost(model: wide), size: CGSize(width: 1300, height: 820), dark: true)
        let narrow = try await page(r, work: MyWorkTarget(account: account, kind: .bug))
        try render("work-narrow", WorkspaceOverviewHost(model: narrow), size: CGSize(width: 760, height: 820))
    }

    func testIntegrationsAndMembers() async throws {
        let m = try await page(repo(), section: "integrations")
        try render("integrations", WorkspaceOverviewHost(model: m) {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(height: 120).overlay(Text("connections feature slot"))
        }, size: CGSize(width: 900, height: 460))
        m.nav.setWorkspaceSection("members")
        try render("members", WorkspaceOverviewHost(model: m), size: CGSize(width: 800, height: 420))
    }
}
