import CoreDomain
import CoreUI
import XCTest
@testable import ToolZenTao

/// The bug and task lists leave out the columns that would be blank on every row.
@MainActor
final class ZentaoTableColumnsTests: XCTestCase {
    private let palette = AppTheme(settings: AppSettings()).colors

    func testABugListWithNothingResolvedOrDueHasNoSuchColumns() {
        let open = [boardBug("1"), boardBug("2")]
        let shown = ZentaoTableColumns.withoutEmpty(ZentaoTableColumns.bugs(palette: palette), rows: open).map(\.id)
        XCTAssertEqual(shown, ["id", "title", "assignee", "pri", "status"])
    }

    func testOneResolvedBugBringsTheResolutionColumnBack() {
        // The column reads the resolution ZenTao gave the bug itself.
        var resolved = boardBug("3", providerStatus: "resolved")
        resolved.providerEntity = .zentaoBug(ZenTaoBugEntity(product: "p1", resolution: "fixed"))
        let rows = [boardBug("1"), resolved]
        let shown = ZentaoTableColumns.withoutEmpty(ZentaoTableColumns.bugs(palette: palette), rows: rows).map(\.id)
        XCTAssertTrue(shown.contains("resolution"))
        XCTAssertFalse(shown.contains("due"))
    }

    func testATaskListShowsDueOnlyWhenATaskHasADeadline() {
        let soon = AppDateFormatBridge.iso(Date().addingTimeInterval(86_400))
        let columns = ZentaoTableColumns.tasks(palette: palette)
        XCTAssertFalse(ZentaoTableColumns.withoutEmpty(columns, rows: [boardTask("201")]).map(\.id).contains("due"))
        XCTAssertTrue(ZentaoTableColumns.withoutEmpty(columns, rows: [boardTask("201"), boardTask("202", deadline: soon)]).map(\.id).contains("due"))
        // The columns every row fills stay whatever the rows.
        XCTAssertEqual(ZentaoTableColumns.withoutEmpty(columns, rows: []).map(\.id).prefix(3), ["id", "title", "assignee"])
    }
}
