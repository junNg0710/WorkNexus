import CoreDomain
import CoreUI
import XCTest
@testable import FeatureTicketEditor

/// Files dropped anywhere on a bug or task form: pictures into the description, the rest attached; a picture that
/// cannot be uploaded is attached instead.
@MainActor
final class EditorFormDropTests: XCTestCase {
    func testPicturesGoIntoTheTextAndTheRestAreAttached() async {
        let text = HtmlEditingController(html: "<p>Steps</p>")
        var attached: [String] = []
        var uploaded: [String] = []
        let drop = EditorFormDrop(text: text, upload: { _, name in
            uploaded.append(name); return name == "broken.png" ? nil : "https://z/\(name)"
        }, attach: { attached += $0.map(\.name) })
        await drop.drop([DroppedFile(name: "shot.png", bytes: Data([1])), DroppedFile(name: "log.txt", bytes: Data([2])),
                         DroppedFile(name: "broken.png", bytes: Data([3]))])
        XCTAssertEqual(uploaded, ["shot.png", "broken.png"])
        XCTAssertTrue(text.html.contains("https://z/shot.png"))
        XCTAssertEqual(attached, ["log.txt", "broken.png"], "nothing dropped is lost")
    }
}
