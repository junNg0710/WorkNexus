import CoreDomain
import CoreTools
import XCTest
@testable import FeatureTicketEditor

/// A ticket made from chat messages takes their pictures along: uploaded under the new form's own id and shown where
/// the messages stood.
@MainActor
final class PrefillPicturesTests: XCTestCase {
    private func picture(_ n: Int, _ name: String) -> TicketEditorPrefill.Picture {
        TicketEditorPrefill.Picture(token: "{{chat-picture-\(n)}}", name: name, data: Data([UInt8(n)]))
    }

    func testEachPictureIsUploadedAndStandsWhereItsTokenWas() async {
        let prefill = TicketEditorPrefill(title: "t", bodyHtml: "<p>An:</p><p>{{chat-picture-1}}</p><p>{{chat-picture-2}}</p>",
                                          pictures: [picture(1, "a.png"), picture(2, "b.png")])
        var sent: [String] = []
        let html = await PlacePrefillPictures()(prefill) { data, name in sent.append("\(name):\(data.count)"); return "/f?n=\(name)&t=\"x\"" }
        XCTAssertEqual(sent, ["a.png:1", "b.png:1"])
        XCTAssertEqual(html, "<p>An:</p><p><img src=\"/f?n=a.png&amp;t=&quot;x&quot;\" /></p><p><img src=\"/f?n=b.png&amp;t=&quot;x&quot;\" /></p>")
    }

    func testAPictureThatCouldNotBeUploadedStaysNamedAndOneNotInTheBodyIsNotUploaded() async {
        let prefill = TicketEditorPrefill(title: "t", bodyHtml: "<p>{{chat-picture-1}}</p>", pictures: [picture(1, "a<b>.png"), picture(2, "gone.png")])
        var sent = 0
        let html = await PlacePrefillPictures()(prefill) { _, _ in sent += 1; return nil }
        XCTAssertEqual(html, "<p>a&lt;b&gt;.png</p>")
        XCTAssertEqual(sent, 1)
    }

    func testANewBugAndTaskUploadThePicturesUnderTheirOwnFormAndKeepTheDraftAtOnce() async {
        let prefill = TicketEditorPrefill(title: "Login fails", bodyHtml: "<p>{{chat-picture-1}}</p><p>{{chat-picture-2}}</p>",
                                          pictures: [picture(1, "a.png"), picture(2, "b.png")])
        let editor = FakeEditor(), drafts = FakeDrafts()
        editor.refusedUploads = ["b.png"]
        let gateway = TicketEditorGateway(editor: editor, drafts: drafts, members: FakeMembers())
        let bug = BugEditorController(launch: .newBug(accountId: "a"), gateway: gateway, autosaveDelay: .milliseconds(10), prefill: prefill)
        await bug.load()
        let uid = bug.state?.uid ?? "?"
        XCTAssertEqual(editor.uploads, ["\(uid):a.png", "\(uid):b.png"], "under the form's own upload id, or ZenTao drops them")
        XCTAssertEqual(bug.state?.draft.steps, "<p><img src=\"/file-read-1.png\" /></p><p>b.png</p>")
        // Written by the messages it quotes: kept without a keystroke.
        for _ in 0..<100 where drafts.saves == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(drafts.all.first?.id, bug.state?.draftId)
        XCTAssertNotNil(bug.state?.draftSavedAt)
        await bug.close()

        let task = TaskEditorController(launch: .newTask(accountId: "a", executionId: "5"), gateway: gateway, prefill: prefill)
        await task.load()
        XCTAssertEqual(task.state?.draft.desc, "<p><img src=\"/file-read-3.png\" /></p><p>b.png</p>")
        XCTAssertEqual(editor.uploads.count, 4)
        await task.close()
    }
}
