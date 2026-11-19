import CoreDomain
import Foundation
import XCTest
@testable import FeaturePanicSwitch

/// Ported from: test/features/panic_switch/panic_switch_runtime_test.dart + run_panic_switch_test.dart (+ the triple click)
@MainActor
final class PanicSwitchRuntimeTests: XCTestCase {
    private let studio = AppRef(id: "com.google.android.studio", name: "Android Studio")
    private let slack = AppRef(id: "com.tinyspeck.slackmacgap", name: "Slack")
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

    private func sticker() -> PanicIncomingMessage {
        PanicIncomingMessage(accountId: "a1", chatGid: "g1", senderId: 7, sentAt: now, imageName: PanicSwitchConstants.stickerFileName)
    }

    func testSwitchesOncePerDebounceWindow() async {
        let r = runtime(PanicSwitchConfig(chatGid: "g1", allowedSenderIds: [7]))
        _ = await r.onIncoming(sticker())
        now += 10
        _ = await r.onIncoming(sticker())
        XCTAssertEqual(apps.calls, [.hideSelf])

        now += 60
        _ = await r.onIncoming(sticker())
        XCTAssertEqual(apps.calls, [.hideSelf, .hideSelf])
    }

    /// The one who raises the alert hides too, once the sticker is out — at most once per debounce window.
    func testTheAlertSendsTheStickerThenSwitchesHereOncePerDebounceWindow() async {
        let r = runtime(PanicSwitchConfig(chatGid: "g1"))
        _ = await r.onAlert()
        _ = await r.onAlert()
        XCTAssertEqual(chats.sent.map(\.chatGid), ["g1"])
        XCTAssertEqual(apps.calls, [.hideSelf])
    }

    /// A sticker that could not be sent does not hide this computer: nobody else hides either.
    func testAFailedSendDoesNotSwitchHere() async {
        chats.sendResult = .failure(.network("server down"))
        let r = runtime(PanicSwitchConfig(chatGid: "g1"))
        let result = await r.onAlert()
        XCTAssertTrue(apps.calls.isEmpty)
        XCTAssertEqual(result.failure, .network("server down"))
    }

    /// Switched off ("enabled" off: this computer does not switch), the alert is still sent.
    func testWithSwitchingOffTheAlertIsOnlySent() async {
        let r = runtime(PanicSwitchConfig(enabled: false, chatGid: "g1"))
        _ = await r.onAlert()
        XCTAssertEqual(chats.sent.map(\.chatGid), ["g1"])
        XCTAssertTrue(apps.calls.isEmpty)
    }

    func testSentToYourselfAlsoSwitchesAppsHere() async {
        chats.sendResult = .failure(.network("server down"))
        let r = runtime(PanicSwitchConfig(testMode: true, testChatGid: "cloud", testChatIsSelf: true))

        let result = await r.onAlert()

        // Switched even though the chat server is down; the send failure is still reported.
        XCTAssertEqual(apps.calls, [.hideSelf])
        XCTAssertEqual(chats.sent.map(\.chatGid), ["cloud"])
        XCTAssertEqual(result.failure, .network("server down"))
    }

    func testRunNowSwitchesWithoutAnyChat() async {
        _ = await runtime(PanicSwitchConfig(chatGid: "g1")).runNow()
        XCTAssertEqual(apps.calls, [.hideSelf])
        XCTAssertTrue(chats.sent.isEmpty)
    }

    func testTripleClickCounterStartsOverAfterAPause() {
        var counter = TripleClickCounter(maxGap: 0.5)
        let t = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(counter.click(at: t))
        XCTAssertFalse(counter.click(at: t + 0.4))
        XCTAssertFalse(counter.click(at: t + 1.5))   // too late: counts as the first again
        XCTAssertFalse(counter.click(at: t + 1.8))
        XCTAssertTrue(counter.click(at: t + 2.1))
    }

    // MARK: RunPanicSwitch

    func testActivatesTheTargetHidesTheOthersThenItself() async {
        let result = await RunPanicSwitch(apps)(PanicSwitchConfig(targetApp: studio, appsToHide: [slack, studio]))
        XCTAssertNotNil(result.value)
        XCTAssertEqual(apps.calls, [.activate(studio.id), .hide(slack.id), .hideSelf])
    }

    func testKeepsGoingAfterAFailureAndReturnsIt() async {
        apps.activateResult = .failure(.unexpected("no"))
        let result = await RunPanicSwitch(apps)(PanicSwitchConfig(targetApp: studio, appsToHide: [slack]))
        XCTAssertEqual(result.failure, .unexpected("no"))
        XCTAssertEqual(apps.calls, [.activate(studio.id), .hide(slack.id), .hideSelf])
    }

    func testSkipsHidingItselfWhenTurnedOff() async {
        _ = await RunPanicSwitch(apps)(PanicSwitchConfig(hideSelf: false))
        XCTAssertTrue(apps.calls.isEmpty)
    }
}
