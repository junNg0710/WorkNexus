import CoreDomain
import XCTest
@testable import ToolZenTao

/// Ported from: test/unit/build_subtask_tree_test.dart (+ the visible-rows walk of test/widget/subtask_list_tree_test.dart).
final class BuildSubtaskTreeTests: XCTestCase {
    private let build = BuildSubtaskTree()

    private func sub(_ id: String, parent: String? = nil) -> TicketSubtask {
        TicketSubtask(id: id, title: "Task \(id)", status: .todo, parentId: parent)
    }

    private func ids(_ nodes: [SubtaskNode]) -> [String] { nodes.map(\.subtask.id) }

    func testNestsGrandchildrenUnderTheirParentNotBesideIt() {
        let tree = build(SubtaskTreeInput(parentId: "1", subtasks: [
            sub("10", parent: "1"), sub("11", parent: "1"), sub("20", parent: "10"),
            sub("21", parent: "10"), sub("30", parent: "20"), sub("22", parent: "11"),
        ]))
        XCTAssertEqual(ids(tree.roots), ["10", "11"])
        XCTAssertEqual(ids(tree.roots[0].children), ["20", "21"])
        XCTAssertEqual(ids(tree.roots[0].children[0].children), ["30"])
        XCTAssertEqual(ids(tree.roots[1].children), ["22"])
        XCTAssertEqual(tree.total, 6)
        XCTAssertTrue(tree.isNested)
    }

    func testAFlatListStaysFlatAndKeepsItsOrder() {
        let tree = build(SubtaskTreeInput(parentId: "1", subtasks: [sub("12", parent: "1"), sub("10", parent: "1")]))
        XCTAssertEqual(ids(tree.roots), ["12", "10"])
        XCTAssertFalse(tree.isNested)
    }

    func testSubtasksWithAnUnknownOrMissingParentAreDirectSubtasks() {
        let tree = build(SubtaskTreeInput(parentId: "1", subtasks: [sub("10"), sub("11", parent: "99")]))
        XCTAssertEqual(ids(tree.roots), ["10", "11"])
    }

    func testAParentLoopSurfacesItsMembersInsteadOfDroppingThem() {
        let tree = build(SubtaskTreeInput(parentId: "1", subtasks: [
            sub("10", parent: "1"), sub("20", parent: "21"), sub("21", parent: "20"), sub("30", parent: "30"),
        ]))
        XCTAssertEqual(ids(tree.roots), ["10", "30", "20"])
        XCTAssertEqual(ids(tree.roots[2].children), ["21"])
        XCTAssertEqual(tree.total, 4)
    }

    func testOnlyAnExpandedSubtaskShowsItsOwnOneLevelDeeper() {
        let tree = build(SubtaskTreeInput(parentId: "1", subtasks: [
            sub("10", parent: "1"), sub("11", parent: "1"), sub("20", parent: "10"), sub("30", parent: "20"),
        ]))
        func rows(_ expanded: Set<String>) -> [String] { tree.visible(expanded: expanded).map { "\($0.node.subtask.id)@\($0.depth)" } }
        XCTAssertEqual(rows([]), ["10@0", "11@0"])
        XCTAssertEqual(rows(["10"]), ["10@0", "20@1", "11@0"])
        XCTAssertEqual(rows(["10", "20"]), ["10@0", "20@1", "30@2", "11@0"])
        // A folded parent hides its whole branch, even what is expanded below it.
        XCTAssertEqual(rows(["20"]), ["10@0", "11@0"])
    }
}
