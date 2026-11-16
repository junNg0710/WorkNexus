import SwiftUI
import XCTest
@testable import CoreUI

final class AppConfirmFlowTests: XCTestCase {
    /// The rail's "Remove" keeps the item in `removing` and presents the dialog through a binding that clears it again.
    func testTheActionStillSeesTheStateThatDismissingClears() {
        var removing: String? = "xddlabs"
        let presented = Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
        var removed: String?
        AppConfirmFlow.confirm(isPresented: presented) { removed = removing }
        XCTAssertEqual(removed, "xddlabs", "the action ran before the dialog cleared its state")
        XCTAssertNil(removing, "and the dialog was dismissed afterwards")
    }
}
