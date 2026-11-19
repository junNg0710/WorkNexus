import CoreDomain
import Foundation
import XCTest
@testable import FeaturePanicSwitch

/// Ported from: test/features/panic_switch/panic_switch_runtime_test.dart + run_panic_switch_test.dart (the floating
/// button's triggers are the pet's here)
@MainActor
final class PanicSwitchRuntimeTests: XCTestCase {
    private let studio = AppRef(id: "com.google.android.studio", name: "Android Studio")
    private let slack = AppRef(id: "com.tinyspeck.slackmacgap", name: "Slack")
    private let config = PanicSwitchConfig(chatGid: "g1", allowedSenderIds: [7])
    private var now = Date(timeIntervalSince1970: 1_795_000_000)
    private var apps: FakeAppSwitcher!
    private var chats: FakeChatGateway!

    override func setUp() async throws {
        apps = FakeAppSwitcher(); chats = FakeChatGateway()
    }

    private func runtime(_ config: PanicSwitchConfig) -> PanicSwitchRuntime {
        PanicSwitchRuntime(account: { panicAccount() }, config: { config }, run: RunPanicSwitch(apps),
                           send: SendPanicSticker(chats, FakeSticker()), clock: { [unowned self] in now })
    }

    private func sticker(chatGid: String = "g1", name: String = PanicSwitchConstants.stickerFileName) -> PanicIncomingMessage {
        PanicIncomingMessage(accountId: "a1", chatGid: chatGid, senderId: 7, sentAt: now, imageName: name)
    }

    func testSwitchesOncePerDebounceWindow() async {
        let r = runtime(config)
        _ = await r.onIncoming(sticker())
        now += 10
        _ = await r.onIncoming(sticker())
        XCTAssertEqual(apps.calls, FakeAppSwitcher.bareSwitch)

        now += 60
        _ = await r.onIncoming(sticker())
        XCTAssertEqual(apps.calls, FakeAppSwitcher.bareSwitch + FakeAppSwitcher.bareSwitch)
    }

    func testSendsTheStickerToTheGroupOncePerDebounceWindow() async {
        let r = runtime(config)
        _ = await r.onPetTriggered(.release)
        _ = await r.onPetTriggered(.release)
        XCTAssertEqual(chats.sent.map(\.chatGid), ["g1"])
        XCTAssertEqual(chats.sent.map(\.name), [PanicSwitchConstants.stickerFileName])
    }

    func testDemoAndReleaseRunSideBySideEachDebounced() async {
        var demo = config; demo.demoMode = true; demo.demoChatGid = "dm"
        let r = runtime(demo)

        _ = await r.onPetTriggered(.release)
        _ = await r.onPetTriggered(.demo)
        _ = await r.onPetTriggered(.demo)
        XCTAssertEqual(chats.sent.map(\.chatGid), ["g1", "dm"])
        XCTAssertEqual(chats.sent.map(\.name), ["worknexus-thayvo-v1.png", "worknexus-thayvo-demo-v1.png"])
        XCTAssertEqual(apps.calls, FakeAppSwitcher.bareSwitch + FakeAppSwitcher.bareSwitch, "each trigger switched here once")
        apps.calls = []

        // The pet's own triggers count for the debounce of each; a minute later both stickers set it off again.
        _ = await r.onIncoming(sticker())
        _ = await r.onIncoming(sticker(chatGid: "dm", name: PanicSwitchConstants.demoStickerFileName))
        XCTAssertTrue(apps.calls.isEmpty)
        now += 60
        _ = await r.onIncoming(sticker())
        _ = await r.onIncoming(sticker(chatGid: "dm", name: PanicSwitchConstants.demoStickerFileName))
        XCTAssertEqual(apps.calls, FakeAppSwitcher.bareSwitch + FakeAppSwitcher.bareSwitch)
    }

    func testTheDemoTriggerDoesNothingWithoutDemoMode() async {
        _ = await runtime(config).onPetTriggered(.demo)
        XCTAssertTrue(chats.sent.isEmpty)
        XCTAssertTrue(apps.calls.isEmpty)
    }

    /// Switching comes first, so it works even with the chat server down; the send failure is still reported.
    func testThePetSwitchesAppsHereTooThenSends() async {
        chats.sendResult = .failure(.network("server down"))
        let result = await runtime(config).onPetTriggered(.release)

        XCTAssertEqual(apps.calls, FakeAppSwitcher.bareSwitch)
        XCTAssertEqual(chats.sent.map(\.chatGid), ["g1"])
        XCTAssertEqual(result.failure, .network("server down"))
    }

    func testTurnedOffThePetNeitherSwitchesNorSends() async {
        var off = config; off.enabled = false
        _ = await runtime(off).onPetTriggered(.release)
        XCTAssertTrue(apps.calls.isEmpty)
        XCTAssertTrue(chats.sent.isEmpty)
    }

    // MARK: RunPanicSwitch

    func testHidesAllButTheAppsToOpenOpensThemFirstOnTopThenItself() async {
        let result = await RunPanicSwitch(apps)(PanicSwitchConfig(appsToOpen: [studio, slack]))
        XCTAssertNotNil(result.value)
        XCTAssertEqual(apps.calls, [.hideOthers([studio.id, slack.id]), .activate(slack.id), .activate(studio.id), .hideSelf])
    }

    func testWithNoAppToOpenStillHidesEverythingElse() async {
        _ = await RunPanicSwitch(apps)(PanicSwitchConfig())
        XCTAssertEqual(apps.calls, [.hideOthers([]), .hideSelf])
    }

    func testKeepsGoingAfterAFailureAndReturnsIt() async {
        apps.activateResult = .failure(.unexpected("no"))
        let result = await RunPanicSwitch(apps)(PanicSwitchConfig(appsToOpen: [studio]))
        XCTAssertEqual(result.failure, .unexpected("no"))
        XCTAssertEqual(apps.calls, [.hideOthers([studio.id]), .activate(studio.id), .hideSelf])
    }
}
