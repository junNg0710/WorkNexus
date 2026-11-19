import CoreDomain
import Foundation
import XCTest
@testable import FeaturePanicSwitch

/// Ported from: test/features/panic_switch/panic_switch_runtime_test.dart ("shows the overlay with the sticker image") and
/// lib/features/panic_switch/presentation/widgets/panic_switch_listener.dart (the team group picked by name, the listener).
@MainActor
final class PanicSwitchModelTests: XCTestCase {
    private func model(_ config: PanicSwitchConfig, chats: FakeChatGateway, apps: FakeAppSwitcher? = nil,
                       overlay: FakeOverlay? = nil, repository: MemoryConfigRepository? = nil,
                       accounts: [Account] = [panicAccount()]) -> PanicSwitchModel {
        PanicSwitchModel(PanicSwitchDependencies(
            repository: repository ?? MemoryConfigRepository(config), chats: chats, apps: apps ?? FakeAppSwitcher(),
            overlay: overlay ?? FakeOverlay(),
            sticker: FakeSticker(result: .success(Data([9]))), accounts: { AsyncStream { $0.yield(accounts); $0.finish() } }))
    }

    /// The pet's gesture (not a floating sticker button) sets off the official trigger, once there is a group and it is on:
    /// this computer switches, and the sticker goes to the team group.
    func testThePetSetsOffTheOfficialTriggerOnceThereIsAGroupAndNoButtonShows() async {
        let overlay = FakeOverlay(), chats = FakeChatGateway(), apps = FakeAppSwitcher()
        let m = model(PanicSwitchConfig(chatGid: "g1"), chats: chats, apps: apps, overlay: overlay)
        m.start()
        let armed = await eventually { m.petArmed }
        XCTAssertTrue(armed)
        XCTAssertEqual(m.petGesture, .hold)
        XCTAssertFalse(m.demoAvailable, "no demo mode")
        XCTAssertNil(overlay.shown, "the pet is the trigger: no floating sticker button")
        m.petTriggered(.release)
        let sent = await eventually { chats.sent.map(\.chatGid) == ["g1"] && apps.calls == FakeAppSwitcher.bareSwitch }
        XCTAssertTrue(sent, "switched here, and sent")

        await m.edit { $0.overlayVisible = false }
        XCTAssertFalse(m.petArmed)
        XCTAssertNil(m.petGesture)
        m.stop()
    }

    /// "Demo" in the pet's menu is offered with demo mode and a demo chat, and sends the demo sticker there.
    func testThePetOffersTheDemoWithDemoModeAndSendsTheDemoSticker() async {
        let chats = FakeChatGateway(), apps = FakeAppSwitcher()
        let m = model(PanicSwitchConfig(chatGid: "g1", demoMode: true), chats: chats, apps: apps)
        m.start()
        _ = await eventually { m.config != nil && m.account != nil }
        XCTAssertFalse(m.demoAvailable, "no demo chat picked yet")
        m.petTriggered(.demo)
        await m.edit { $0.demoChatGid = "dm" }
        XCTAssertTrue(m.demoAvailable)
        m.petTriggered(.demo)
        let sent = await eventually { chats.sent.map(\.name) == [PanicSwitchConstants.demoStickerFileName] }
        XCTAssertTrue(sent)
        XCTAssertEqual(chats.sent.map(\.chatGid), ["dm"])
        XCTAssertEqual(apps.calls, FakeAppSwitcher.bareSwitch, "switched here too")

        await m.edit { $0.enabled = false }
        XCTAssertFalse(m.demoAvailable, "turned off: no menu item")
        XCTAssertFalse(m.petArmed)
        m.stop()
    }

    /// The gesture chosen is the one the pet is armed with.
    func testThePetIsArmedWithTheGestureChosen() async {
        let m = model(PanicSwitchConfig(chatGid: "g1"), chats: FakeChatGateway())
        m.start()
        _ = await eventually { m.petArmed }
        for gesture in PanicPetGesture.allCases {
            await m.edit { $0.petGesture = gesture }
            XCTAssertEqual(m.petGesture, gesture)
        }
        m.stop()
    }

    /// The allowlist is the team group's: the members are those of the team group, whatever the demo chat is.
    func testLoadsTheTeamGroupsMembers() async {
        let chats = FakeChatGateway()
        chats.people = [PanicPerson(userId: 2, account: "zoe", realname: "Zoe", avatarUrl: "https://x/a.png")]
        chats.members = .success([2])
        let m = model(PanicSwitchConfig(chatGid: "g1", demoMode: true, demoChatGid: "dm"), chats: chats)
        m.start()
        _ = await eventually { m.config != nil && m.account != nil }
        await m.loadMembers()
        XCTAssertEqual(m.members, .loaded(chats.people))
        m.stop()
    }

    func testStaysOffForOtherZenTaoServers() async {
        let overlay = FakeOverlay()
        let m = model(PanicSwitchConfig(chatGid: "g1"), chats: FakeChatGateway(), overlay: overlay,
                      accounts: [panicAccount("a1", .zentao, "https://other.example/zentao")])
        m.start()
        _ = await eventually { m.config != nil }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(m.account)
        XCTAssertNil(overlay.shown)
        m.stop()
    }

    func testPicksTheTeamGroupByNameUntilOneIsSet() async {
        let chats = FakeChatGateway()
        chats.chatList = [PanicChatRef(gid: "g7", kind: .group, name: "VN Mobile+Tester")]
        let repository = MemoryConfigRepository()
        let m = model(PanicSwitchConfig(), chats: chats, repository: repository)
        m.start()
        let picked = await eventually { m.config?.chatGid == "g7" }
        XCTAssertTrue(picked)
        XCTAssertEqual(repository.current.chatGid, "g7")
        m.stop()
    }

    func testSwitchesAppsWhenTheStickerArrives() async {
        let chats = FakeChatGateway()
        chats.arriving = [
            PanicIncomingMessage(accountId: "a1", chatGid: "g1", senderId: 7, sentAt: Date(), imageName: "cat.png"),
            PanicIncomingMessage(accountId: "a1", chatGid: "g1", senderId: 7, sentAt: Date(), imageName: PanicSwitchConstants.stickerFileName),
        ]
        let apps = FakeAppSwitcher()
        let m = model(PanicSwitchConfig(chatGid: "g1"), chats: chats, apps: apps)
        m.start()
        _ = await eventually { apps.calls == FakeAppSwitcher.bareSwitch }
        XCTAssertEqual(apps.calls, FakeAppSwitcher.bareSwitch)
        m.stop()
    }

    func testSwitchesAppsWhenTheDemoStickerArrivesInTheDemoChatOnly() async {
        let chats = FakeChatGateway()
        chats.arriving = [
            // The demo sticker in the team group, and the official one in the demo chat: neither is a trigger.
            PanicIncomingMessage(accountId: "a1", chatGid: "g1", senderId: 7, sentAt: Date(), imageName: PanicSwitchConstants.demoStickerFileName),
            PanicIncomingMessage(accountId: "a1", chatGid: "dm", senderId: 7, sentAt: Date(), imageName: PanicSwitchConstants.stickerFileName),
            PanicIncomingMessage(accountId: "a1", chatGid: "dm", senderId: 9, sentAt: Date(), imageName: PanicSwitchConstants.demoStickerFileName),
        ]
        let apps = FakeAppSwitcher()
        let m = model(PanicSwitchConfig(chatGid: "g1", demoMode: true, demoChatGid: "dm", anySender: false), chats: chats, apps: apps)
        m.start()
        _ = await eventually { apps.calls == FakeAppSwitcher.bareSwitch }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(apps.calls, FakeAppSwitcher.bareSwitch, "once, for the demo sticker from anyone in the demo chat")
        m.stop()
    }
}

/// Not in the Flutter app: the pet's gesture — held for 3 s by default, or two or three clicks — kept with the settings.
final class PanicPetGestureTests: XCTestCase {
    func testHoldingIsTheDefaultAndTheChoiceIsKept() throws {
        XCTAssertEqual(PanicSwitchConfigMapper.fromJSON(Data(#"{"enabled":true}"#.utf8)).petGesture, .hold, "older settings")
        var config = PanicSwitchConfig(chatGid: "g1")
        XCTAssertEqual(config.petGesture, .hold)
        for gesture in PanicPetGesture.allCases {
            config.petGesture = gesture
            let back = PanicSwitchConfigMapper.fromJSON(try PanicSwitchConfigMapper.toJSON(config))
            XCTAssertEqual(back.petGesture, gesture)
            XCTAssertEqual(back, config)
        }
        XCTAssertEqual(PanicSwitchConfigMapper.fromJSON(Data(#"{"petGesture":"doubleClick"}"#.utf8)).petGesture, .doubleClick)
        XCTAssertEqual(PanicSwitchConfigMapper.fromJSON(Data(#"{"petGesture":"wiggle"}"#.utf8)).petGesture, .hold)
    }

    /// The hold time is the user's: 3 s by default, kept as set, and kept within 1–30 s.
    func testTheHoldTimeIsKeptWithinItsRange() throws {
        XCTAssertEqual(PanicSwitchConfig().petHoldSeconds, 3)
        var config = PanicSwitchConfig(); config.petHoldSeconds = 7
        XCTAssertEqual(PanicSwitchConfigMapper.fromJSON(try PanicSwitchConfigMapper.toJSON(config)).petHoldSeconds, 7)
        XCTAssertEqual(PanicSwitchConfigMapper.fromJSON(Data(#"{"petHoldSeconds":120}"#.utf8)).petHoldSeconds, 30)
        XCTAssertEqual(PanicSwitchConfigMapper.fromJSON(Data(#"{"petHoldSeconds":0}"#.utf8)).petHoldSeconds, 1)
    }
}
