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

    func testShowsTheOverlayWithTheStickerOnceThereIsAGroup() async {
        let overlay = FakeOverlay()
        let m = model(PanicSwitchConfig(chatGid: "g1"), chats: FakeChatGateway(), overlay: overlay)
        m.start()
        let shown = await eventually { overlay.shown == Data([9]) }
        XCTAssertTrue(shown)

        await m.edit { $0.overlayVisible = false }
        XCTAssertNil(overlay.shown)
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
        _ = await eventually { apps.calls == [.hideSelf] }
        XCTAssertEqual(apps.calls, [.hideSelf])
        m.stop()
    }
}
