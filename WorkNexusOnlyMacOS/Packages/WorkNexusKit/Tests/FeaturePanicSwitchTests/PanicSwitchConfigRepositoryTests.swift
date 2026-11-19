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
        let config = PanicSwitchConfig(enabled: false, overlayVisible: false, chatGid: "g1", testMode: true, testChatGid: "cloud",
                                       testChatIsSelf: true, anySender: false, allowedSenderIds: [3, 7],
                                       targetApp: AppRef(id: "com.google.android.studio", name: "Android Studio"),
                                       appsToHide: [AppRef(id: "com.tinyspeck.slackmacgap", name: "Slack")], hideSelf: false,
                                       debounceSeconds: 90)

        let saved = await repository.save(config)
        XCTAssertNotNil(saved.value)
        let loaded = await repository.load()
        XCTAssertEqual(loaded.value, config)
    }

    func testReadsTheJsonTheFlutterAppWrites() {
        let config = decode(#"{"enabled":true,"overlayVisible":true,"chatGid":"g1","testMode":false,"testChatGid":null,"#
            + #""testChatIsSelf":false,"anySender":false,"allowedSenderIds":[3,"x",7],"#
            + #""targetApp":{"id":"com.apple.Safari","name":"Safari"},"appsToHide":[{"id":"a","name":"A"},{"bad":1}],"#
            + #""hideSelf":true,"debounceSeconds":30}"#)

        XCTAssertEqual(config, PanicSwitchConfig(chatGid: "g1", anySender: false, allowedSenderIds: [3, 7],
                                                 targetApp: AppRef(id: "com.apple.Safari", name: "Safari"),
                                                 appsToHide: [AppRef(id: "a", name: "A")], debounceSeconds: 30))
    }

    func testMovesAnOldSendToMyselfChatIntoTestMode() {
        let config = decode(#"{"chatGid":"40&40","chatIsSelf":true,"debounceSeconds":60}"#)

        XCTAssertNil(config.chatGid)
        XCTAssertTrue(config.testMode)
        XCTAssertEqual(config.testChatGid, "40&40")
        XCTAssertTrue(config.testChatIsSelf)
    }

    func testKeepsTheListeningChatOfTheOldTwoChatTestMode() {
        let config = decode(#"{"testMode":true,"testSendChatGid":"40&40","testSendToSelf":true,"testReceiveChatGid":"g9"}"#)

        XCTAssertEqual(config.testChatGid, "g9")
        XCTAssertFalse(config.testChatIsSelf)
    }

    func testDamagedJsonLoadsTheDefaults() {
        XCTAssertEqual(decode("not json"), PanicSwitchConfig())
    }
}
