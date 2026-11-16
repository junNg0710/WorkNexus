/// Ported from: lib/features/chat/presentation/widgets/chat_person_chip.dart (`_find`), import_sticker_pack_dialog.dart (failure switch)
import CoreDomain
import XCTest
@testable import FeatureChat

final class ChatPersonAndStickerErrorTests: XCTestCase {
    private func user(_ id: Int, _ account: String, _ name: String, deleted: Bool = false) -> ChatUser {
        var u = ChatUser(accountId: "a", userId: id, account: account, realname: name)
        u.deleted = deleted
        return u
    }

    @MainActor func testAPersonIsFoundByLoginBeforeDisplayNameAndDeletedOnesAreSkipped() {
        let users = [user(1, "an", "Bình"), user(2, "binh", "An"), user(3, "old", "Cũ", deleted: true)]
        // "an" is user 1's login and user 2's name: the login wins.
        XCTAssertEqual(ChatPersonDirectory.find(users, "An")?.userId, 1)
        XCTAssertEqual(ChatPersonDirectory.find(users, " BÌNH ")?.userId, 1)
        XCTAssertEqual(ChatPersonDirectory.find(users, "binh")?.userId, 2)
        XCTAssertNil(ChatPersonDirectory.find(users, "old"))
        XCTAssertNil(ChatPersonDirectory.find(users, "Cũ"))
        XCTAssertNil(ChatPersonDirectory.find(users, "  "))
    }

    func testEachImportFailureShowsItsOwnMessage() {
        XCTAssertEqual(StickerImportErrors.shown(for: .auth("x")), .token("Telegram refused this bot token."))
        XCTAssertEqual(StickerImportErrors.shown(for: .notFound("x")), .general("No sticker set has this link."))
        XCTAssertEqual(StickerImportErrors.shown(for: .network("x")), .general("Telegram could not be reached."))
        XCTAssertEqual(StickerImportErrors.shown(for: .validation("x")), .general("Paste a link like https://t.me/addstickers/Name"))
        XCTAssertEqual(StickerImportErrors.shown(for: .unexpected("x")), .general("The sticker set could not be added."))
    }
}
