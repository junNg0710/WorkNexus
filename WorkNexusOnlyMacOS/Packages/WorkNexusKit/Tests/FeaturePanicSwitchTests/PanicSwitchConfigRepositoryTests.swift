import Foundation
import XCTest
@testable import FeaturePanicSwitch

/// Ported from: test/features/panic_switch/local_panic_switch_config_repository_test.dart (a temporary file instead of the
/// in-memory database).
final class PanicSwitchConfigRepositoryTests: XCTestCase {
    private var dir: URL!
    private var repository: FilePanicSwitchConfigRepository!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("panic-\(UUID().uuidString)", isDirectory: true)
        repository = FilePanicSwitchConfigRepository(url: dir.appendingPathComponent("panic_switch.json"))
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func decode(_ json: String) -> PanicSwitchConfig { PanicSwitchConfigMapper.fromJSON(Data(json.utf8)) }

    func testLoadsTheDefaultsBeforeAnythingIsSaved() async {
        let loaded = await repository.load()
        XCTAssertEqual(loaded.value, PanicSwitchConfig())
    }

    func testRoundTripsEveryField() async {
        var config = PanicSwitchConfig(enabled: false, overlayVisible: false, chatGid: "g1", demoMode: true, demoChatGid: "cloud",
                                       anySender: false, allowedSenderIds: [3, 7],
                                       appsToOpen: [AppRef(id: "com.google.android.studio", name: "Android Studio"),
                                                    AppRef(id: "com.tinyspeck.slackmacgap", name: "Slack")],
                                       debounceSeconds: 90)
        config.petGesture = .doubleClick
        config.petHoldSeconds = 5

        let saved = await repository.save(config)
        XCTAssertNotNil(saved.value)
        let loaded = await repository.load()
        XCTAssertEqual(loaded.value, config)
    }

    /// The keys are the Flutter mapper's (`panic_switch_config_mapper.dart`), plus the pet's own two.
    func testWritesTheKeysTheFlutterAppReads() throws {
        let data = try PanicSwitchConfigMapper.toJSON(PanicSwitchConfig(chatGid: "g1", demoMode: true, demoChatGid: "dm",
                                                                        appsToOpen: [AppRef(id: "a", name: "A")]))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["enabled", "overlayVisible", "chatGid", "demoMode", "demoChatGid", "anySender",
                                        "allowedSenderIds", "appsToOpen", "debounceSeconds", "petGesture", "petHoldSeconds"])
        XCTAssertEqual(json["appsToOpen"] as? [[String: String]], [["id": "a", "name": "A"]])
    }

    func testReadsTheJsonTheFlutterAppWrites() {
        let config = decode(#"{"enabled":true,"overlayVisible":true,"overlaySize":80,"overlayOpacity":0.6,"#
            + #""overlayGesture":"hold","chatGid":"g1","demoMode":true,"demoChatGid":"dm","anySender":false,"#
            + #""allowedSenderIds":[3,"x",7],"appsToOpen":[{"id":"com.apple.Safari","name":"Safari"},{"bad":1}],"#
            + #""debounceSeconds":30}"#)

        XCTAssertEqual(config, PanicSwitchConfig(chatGid: "g1", demoMode: true, demoChatGid: "dm", anySender: false,
                                                 allowedSenderIds: [3, 7],
                                                 appsToOpen: [AppRef(id: "com.apple.Safari", name: "Safari")], debounceSeconds: 30))
    }

    func testMovesAnOldSendToMyselfChatIntoDemoMode() {
        let config = decode(#"{"chatGid":"40&40","chatIsSelf":true,"debounceSeconds":60}"#)

        XCTAssertNil(config.chatGid)
        XCTAssertTrue(config.demoMode)
        XCTAssertEqual(config.demoChatGid, "40&40")
    }

    func testKeepsTheListeningChatOfTheOldTwoChatTestMode() {
        let config = decode(#"{"testMode":true,"testSendChatGid":"40&40","testSendToSelf":true,"testReceiveChatGid":"g9"}"#)

        XCTAssertTrue(config.demoMode)
        XCTAssertEqual(config.demoChatGid, "g9")
    }

    func testTurnsTheSavedTestModeIntoDemoMode() {
        let config = decode(#"{"chatGid":"g1","testMode":true,"testChatGid":"g9","testChatIsSelf":false}"#)

        XCTAssertEqual(config.chatGid, "g1")
        XCTAssertTrue(config.demoMode)
        XCTAssertEqual(config.demoChatGid, "g9")
    }

    /// What this app saved before this port (test mode, one target app, apps to hide, hide WorkNexus) loads as the new shape.
    func testTurnsTheOldTargetAppIntoTheAppsToOpen() {
        let config = decode(#"{"targetApp":{"id":"a.b","name":"AB"},"appsToHide":[{"id":"c.d","name":"CD"}],"hideSelf":false,"#
            + #""testMode":false,"testChatGid":"cloud","petGesture":"tripleClick","petHoldSeconds":4}"#)

        XCTAssertEqual(config.appsToOpen, [AppRef(id: "a.b", name: "AB")])
        XCTAssertFalse(config.demoMode, "test mode was off")
        XCTAssertEqual(config.demoChatGid, "cloud")
        XCTAssertEqual(config.petGesture, .tripleClick)
        XCTAssertEqual(config.petHoldSeconds, 4)
    }

    func testDamagedJsonLoadsTheDefaults() {
        XCTAssertEqual(decode("not json"), PanicSwitchConfig())
    }
}
