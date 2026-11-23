import CoreDomain
import CoreTools
import Foundation
import XCTest
@testable import SharedKit

@MainActor
final class RailPlacesTests: XCTestCase {
    private func make(accounts: [Account]) async -> ShellModel {
        let live = LiveWorkspaces([Workspace(id: "a", name: "Alpha", shortCode: "A", colorValue: 1)], accounts)
        let fake = FakeStore()
        let services = AppServices(tickets: fake, workspaces: live, comments: fake, activity: fake, syncStatus: SyncTests.RecordingStatus(),
                                   settings: BoardControllerTests.FakeSettings(), credentials: fake, sync: BoardControllerTests.NoopSync(),
                                   ticketDetail: BoardControllerTests.NoopSync(), adapters: FakeRegistry())
        let shell = ShellModel(services: services, registry: ToolRegistry(), workspaceStore: MemoryWorkspaceStore())
        shell.opensChatAtLaunch = false
        shell.start()
        for _ in 0..<100 where !(shell.loadedAccounts && shell.loadedWorkspaces) { try? await Task.sleep(for: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(20))
        return shell
    }

    private func account(_ id: String) -> Account { Account(id: id, workspaceId: "a", providerType: .gitlab, handle: id) }
    private func cmd(_ n: Int) -> KeyShortcut { KeyShortcut.byPosition(n)! }
    private func settle() async { try? await Task.sleep(for: .milliseconds(60)) }

    func testThePlacesAreTheRailFromTheTop() async {
        let shell = await make(accounts: [account("g1"), account("g2")])
        var opened: [String] = []
        shell.host.railExtraPlaces = { [RailPlace(id: "miniapp:m1", name: "Jenkins") { opened.append("m1") }] }
        XCTAssertEqual(shell.railPlaces.map(\.id), ["workspace", "account:g1", "account:g2", "miniapp:m1", "settings"])
        // Two accounts of one provider are told apart by their login.
        XCTAssertEqual(shell.railPlaces[1].name, "GitLab · g1")
        XCTAssertEqual(shell.railShortcuts["account:g2"], cmd(3))
        XCTAssertEqual(shell.railShortcuts["settings"], cmd(5))
        XCTAssertEqual(RailTips.place("Jenkins", current: false, folded: false, keys: cmd(4)), "Jenkins (⌘4)")

        XCTAssertTrue(shell.handleRailShortcut(cmd(3)))
        await settle()
        XCTAssertEqual(shell.nav.state.rail, .account("g2"))
        XCTAssertTrue(shell.handleRailShortcut(cmd(4)))
        await settle()
        XCTAssertEqual(opened, ["m1"])
        XCTAssertFalse(shell.handleRailShortcut(cmd(9)), "no ninth place: the keys go on to whoever wants them")
        XCTAssertEqual(shell.nav.state.rail, .account("g2"))
    }

    func testHoldingTheModifiersShowsEachPlacesKey() async {
        let shell = await make(accounts: [account("g1")])
        let chosen = KeyShortcut(keyCode: 38, label: "J", modifiers: .control)
        shell.updateSettings { $0.railShortcuts.assign(chosen, to: "settings", places: shell.railPlaces.map(\.id)) }
        XCTAssertNil(shell.railKeyHint("workspace"), "nothing held, nothing shown")

        // ⌘ held: not at once (a quick ⌘C shows nothing), then the places that open with ⌘ show their number.
        shell.railHints.modifiersChanged(.command, after: .milliseconds(40))
        XCTAssertNil(shell.railKeyHint("workspace"))
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(shell.railKeyHint("workspace"), "1"); XCTAssertEqual(shell.railKeyHint("account:g1"), "2")
        XCTAssertNil(shell.railKeyHint("settings"), "it opens with ⌃J")
        // Already up, ⌃ instead shows at once the places that open with ⌃.
        shell.railHints.modifiersChanged(.control, after: .seconds(5))
        XCTAssertEqual(shell.railKeyHint("settings"), "J"); XCTAssertNil(shell.railKeyHint("workspace"))
        // Let go: gone at once.
        shell.railHints.modifiersChanged([])
        XCTAssertNil(shell.railKeyHint("settings"))

        // Let go before the moment is over, or only ⇧ / ⌥ held: nothing ever shows.
        shell.railHints.modifiersChanged(.command, after: .milliseconds(40))
        shell.railHints.modifiersChanged([])
        shell.railHints.modifiersChanged([.shift, .option], after: .milliseconds(1))
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(shell.railHints.held)

        // Switched off, no place has a key to show.
        shell.railHints.modifiersChanged(.command, after: .milliseconds(1))
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(shell.railKeyHint("workspace"), "1")
        shell.updateSettings { $0.railShortcuts.enabled = false }
        XCTAssertNil(shell.railKeyHint("workspace"))
    }

    func testChosenKeysOpenTheirPlaceAndOffNothingDoes() async {
        let shell = await make(accounts: [account("g1")])
        let chosen = KeyShortcut(keyCode: 38, label: "J", modifiers: .control)
        shell.updateSettings { $0.railShortcuts.assign(chosen, to: "settings", places: shell.railPlaces.map(\.id)) }
        XCTAssertTrue(shell.handleRailShortcut(chosen))
        await settle()
        XCTAssertEqual(shell.nav.state.rail, .settings)
        XCTAssertFalse(shell.handleRailShortcut(cmd(3)), "Settings no longer answers to its position")

        shell.updateSettings { $0.railShortcuts.enabled = false }
        XCTAssertFalse(shell.handleRailShortcut(cmd(1)))
        XCTAssertFalse(shell.handleRailShortcut(chosen))
        await settle()
        XCTAssertEqual(shell.nav.state.rail, .settings)
    }
}
