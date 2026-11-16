import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureTicketEditor

/// Renders the editor pages off-screen (an in-memory fake `ZenTaoTicketEditor`) so layout crashes show up in the
/// tests and the PNGs in /tmp/wn-feat-render/editor-*.png can be eyeballed. Asserts only that something was drawn.
@MainActor
final class RenderSmokeTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-feat-render")

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false, wait: TimeInterval = 0.9) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.environment(\.appTheme, theme).frame(width: size.width, height: size.height)
            .background(theme.colors.bg).environment(\.colorScheme, theme.colorScheme))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
    }

    private func gateway() -> TicketEditorGateway {
        let editor = FakeEditor()
        var bug = BugDraft(id: "6492", product: "7")
        bug.title = "Feed: video autoplay is delayed"; bug.openedBuilds = ["trunk", "b1"]; bug.severity = 2; bug.pri = 1
        bug.assignedTo = "thanh"; bug.deadline = "2026-11-20"; bug.steps = "<p>Open the feed and scroll to a video.</p>"
        editor.bugForm = BugForm(draft: bug, options: FakeEditor.bugOptions)
        var task = TaskDraft(id: "88", execution: "5")
        task.name = "Write the migration notes"; task.estStarted = "2026-11-16"; task.deadline = "2026-11-18"; task.estimate = 6
        task.consumed = 2; task.left = 4; task.status = "doing"; task.desc = "<p>Cover the drafts table.</p>"
        editor.taskForm = TaskForm(draft: task, options: FakeEditor.taskOptions)
        let kept = ZenTaoSavedDraft(id: "d1", accountId: "a", uid: "u", updatedAt: Date().addingTimeInterval(-300), content: .bug(BugDraft(product: "7")))
        return TicketEditorGateway(editor: editor, drafts: FakeDrafts([kept]), members: FakeMembers())
    }

    func testBugEditorRenders() throws {
        try render("editor-bug", BugEditorView(launch: .editBug(accountId: "a", bugId: "6492"), gateway: gateway(), actions: EditorActions()),
                   size: CGSize(width: 1240, height: 1100))
    }

    func testNewBugMissingFieldsAreMarked() async {
        let c = BugEditorController(launch: .newBug(accountId: "a"), gateway: TicketEditorGateway(editor: FakeEditor()))
        await c.load()
        c.edit { $0.openedBuilds = [] }
        _ = await c.save()
        XCTAssertEqual(c.state?.missing, [.title, .openedBuilds])
        await c.close()
    }

    // A sync test: the view's `.task` needs the main actor while the run loop spins.
    func testNewBugRendersDark() throws {
        try render("editor-bug-new-dark", BugEditorView(launch: .newBug(accountId: "a"), gateway: gateway(), actions: EditorActions()),
                   size: CGSize(width: 1000, height: 1000), dark: true)
    }

    func testTaskEditorRenders() throws {
        try render("editor-task", TaskEditorView(launch: .editTask(accountId: "a", taskId: "88"), gateway: gateway(), actions: EditorActions()),
                   size: CGSize(width: 1100, height: 1250))
    }

    func testNewTaskRenders() throws {
        try render("editor-task-new", TaskEditorView(launch: .newTask(accountId: "a", executionId: "5"), gateway: gateway(), actions: EditorActions()),
                   size: CGSize(width: 1100, height: 1100))
    }

    func testMissingEditorRendersErrorState() throws {
        try render("editor-unavailable",
                   TicketEditorView(launch: .newBug(accountId: "a")), size: CGSize(width: 700, height: 400), wait: 0.4)
    }
}
