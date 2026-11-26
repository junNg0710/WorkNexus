// Not in the Flutter app: the files attached to a ZenTao comment show with it.
import CoreDomain
import XCTest
@testable import ToolZenTao

final class ZenTaoCommentFilesTests: XCTestCase {
    private let base = "https://zt.example.com/zentao"

    func testAPictureAttachedToACommentShowsAfterItsText() {
        let action = ZenTaoAction(json: [
            "id": 762130, "action": "commented", "comment": "Change icon",
            "files": ["34601": ["id": 34601, "title": "9632b7e5.png", "extension": "png", "size": 233779] as [String: Any]] as [String: Any],
        ])
        XCTAssertEqual(action.files.count, 1)
        XCTAssertEqual(zentaoCommentBody(action, baseUrl: base),
                       "Change icon<p><img src=\"https://zt.example.com/zentao/file-download-34601.png\" alt=\"9632b7e5.png\" /></p>")
    }

    func testAnyOtherFileIsALinkUnderItsName() {
        let action = ZenTaoAction(json: [
            "action": "commented", "comment": "<p>Log attached</p>",
            "files": [["id": "7", "title": "run <1> & \"2\".log", "extension": "LOG", "url": "https://zt.example.com/zentao/file-download-7.log"] as [String: Any]],
        ])
        XCTAssertEqual(zentaoCommentBody(action, baseUrl: base),
                       "<p>Log attached</p><p><a href=\"https://zt.example.com/zentao/file-download-7.log\">run &lt;1&gt; &amp; &quot;2&quot;.log</a></p>")
    }

    func testFilesComeInUploadOrderFromAListOrAnIdKeyedObject() {
        let keyed = ZenTaoAction(json: ["files": ["12": ["id": 12, "title": "b.png", "extension": "png"] as [String: Any],
                                                   "9": ["id": 9, "title": "a.png", "extension": "png"] as [String: Any]] as [String: Any]])
        XCTAssertEqual(keyed.files.compactMap { $0.title as? String }, ["a.png", "b.png"])
        let listed = ZenTaoAction(json: ["files": [["id": 12, "title": "b.png"] as [String: Any], ["id": 9, "title": "a.png"] as [String: Any]]])
        XCTAssertEqual(listed.files.compactMap { $0.title as? String }, ["a.png", "b.png"])
    }

    func testACommentWithoutFilesIsItsTextAndOneWithOnlyAFileIsThatFile() {
        XCTAssertEqual(zentaoCommentBody(ZenTaoAction(json: ["comment": "<p>Done</p>"]), baseUrl: base), "<p>Done</p>")
        XCTAssertEqual(zentaoCommentBody(ZenTaoAction(json: ["comment": "<p>Done</p>", "files": [] as [Any]]), baseUrl: base), "<p>Done</p>")
        let onlyFile = ZenTaoAction(json: ["comment": "", "files": [["id": 3, "title": "shot.jpg", "extension": "jpg"] as [String: Any]]])
        XCTAssertEqual(zentaoCommentBody(onlyFile, baseUrl: base),
                       "<p><img src=\"https://zt.example.com/zentao/file-download-3.jpg\" alt=\"shot.jpg\" /></p>")
    }

    func testAnActivityRowNamesItsFilesOnce() {
        let action = ZenTaoAction(json: ["action": "resolved", "comment": "Added Files clip.mp4\r\n<p>fixed</p>",
                                         "files": [["id": 5, "title": "clip.mp4", "extension": "mp4"] as [String: Any],
                                                   ["id": 6, "title": "after.png", "extension": "png"] as [String: Any]]])
        let noted = zentaoActionAttachments(action.commentText).files
        XCTAssertEqual(zentaoActivityFileNames(action, noted: noted, baseUrl: base), ["clip.mp4", "after.png"])
    }
}
