import Foundation
import XCTest
@testable import FeatureChat

// Ported from: test/domain/chat/suggest_stickers_test.dart

private func sticker(_ id: String, _ emoji: String, _ words: [String] = []) -> ChatSticker {
    ChatSticker(id: id, pack: "p", name: "\(id).webp", location: id, emoji: emoji, keywords: words)
}

private let laugh = sticker("laugh", "😂🤣"), rofl = sticker("rofl", "🤣"), thanks = sticker("thanks", "🙏😊", ["cam on"])
private let smile = sticker("smile", "😊"), ok = sticker("ok", "👌👍"), heart = sticker("heart", "❤️"), coder = sticker("coder", "👨‍💻")
private let think = sticker("think", "🤔"), shock = sticker("shock", "😱😳"), seen = sticker("seen", "👀"), nope = sticker("nope", "🙅")
private let plead = sticker("plead", "🥺"), untagged = sticker("mine", "")
private let all = [laugh, rofl, thanks, smile, ok, heart, coder, think, shock, seen, nope, plead, untagged]

private func day(_ d: Int, _ h: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }

private func message(_ text: String, mine: Bool = false, at: Date? = nil, content: MessageContent? = nil) -> ChatMessage {
    ChatMessage(accountId: "a", gid: "g", chatGid: "c", senderId: 2, sentAt: at ?? day(18, 10), content: content ?? .text(text), isMine: mine)
}

final class StickerMatchingTests: XCTestCase {
    func testFindsEmojiWholeWithoutThePresentationSelector() {
        XCTAssertEqual(StickerMatching.emojiIn("ok 👨‍💻 and ❤️ 👍🏽"), ["👨‍💻", "❤", "👍🏽"])
    }

    func testFindsWholeWordsOnlyTheLastTypedFirst() {
        let words = StickerMatching.words("Cảm ơn, haha!")
        XCTAssertEqual(words, "cam on haha")
        XCTAssertEqual(StickerMatching.keysIn(words, ["haha", "cam on", "on h"]), ["haha", "cam on"])
        // "yêu cầu" is not "yêu".
        XCTAssertEqual(StickerMatching.keysIn("yeu cau review", ["iu"]), [])
    }

    /// Every lexicon entry stands for at least one emoji the matcher finds.
    func testTheLexiconsHoldEmojiOnly() {
        for (_, emoji) in StickerKeywords.typed + StickerKeywords.reply + StickerKeywords.symbols {
            XCTAssertFalse(StickerMatching.emojiIn(emoji).isEmpty, emoji)
        }
    }
}

final class SuggestStickersTests: XCTestCase {
    private let suggest = SuggestStickers()

    func testAStickersOwnWordsComeFirstAndReplaceTheDraft() {
        let r = suggest("Cảm ơn", all)
        XCTAssertEqual(r.stickers.first, thanks)
        XCTAssertTrue(r.replacesDraft)
    }

    func testWordsPickStickersByEmojiAPrimaryEmojiFirst() {
        let r = suggest("haha", all)
        XCTAssertEqual(r.stickers, [laugh, rofl])
        XCTAssertTrue(r.replacesDraft)
    }

    func testATypedEmojiPicksStickersCarryingIt() {
        XCTAssertEqual(suggest("❤️", all).stickers, [heart])
        XCTAssertEqual(suggest("đang code 👨‍💻", all).stickers.first, coder)
    }

    func testPunctuationAndEmoticonsTypedAlonePickStickers() {
        let question = suggest("???", all)
        XCTAssertEqual(question.stickers.first, think)
        XCTAssertTrue(question.replacesDraft)
        XCTAssertEqual(suggest("?!", all).stickers.first, shock)
        XCTAssertEqual(suggest("=)))", all).stickers.first, laugh)
        XCTAssertEqual(suggest("<3", all).stickers, [heart])
        XCTAssertEqual(suggest(".", all).stickers, [])
    }

    func testANumberTypedAloneSaysYesOrNoAndIsReplaced() {
        let yes = suggest("1", all)
        XCTAssertEqual(Array(yes.stickers.prefix(2)), [ok, seen])
        XCTAssertTrue(yes.replacesDraft)
        XCTAssertEqual(suggest(" 0 ", all).stickers.first, nope)
        // Inside a sentence a number is only a number.
        XCTAssertEqual(suggest("còn 1 bug", all).stickers, [])
    }

    func testAQuestionMarkEndingASentenceAddsAThinkingSticker() {
        let r = suggest("xong chưa?", all)
        XCTAssertTrue(r.stickers.contains(think))
        XCTAssertFalse(r.replacesDraft)
    }

    func testALongerDraftKeepsItsTextWhenAStickerIsSent() {
        let r = suggest("ok anh để em xem", all)
        // "xem" (look) is the last word, so its sticker leads.
        XCTAssertEqual(Array(r.stickers.prefix(2)), [seen, ok])
        XCTAssertFalse(r.replacesDraft)
    }

    func testNothingForLongDraftsUnknownWordsOrUntaggedStickers() {
        XCTAssertEqual(suggest("haha nhưng mà cái này dài quá rồi đấy", all).stickers, [])
        XCTAssertEqual(suggest("deadline thứ sáu", all).stickers, [])
        XCTAssertEqual(suggest("", all).stickers, [])
        XCTAssertEqual(suggest("haha", [untagged]).stickers, [])
    }
}

final class SuggestReplyStickersTests: XCTestCase {
    private let suggest = SuggestReplyStickers()
    private let now = day(18, 11)

    func testThanksIsAnsweredWithASmileNotThanksBack() {
        XCTAssertEqual(suggest(message("Cảm ơn anh nhé"), all, now: now).first, smile)
    }

    func testALoneQuestionMarkIsAnsweredWithAThinkingSticker() {
        XCTAssertEqual(suggest(message("?"), all, now: now).first, think)
        XCTAssertEqual(suggest(message("=))"), all, now: now).first, laugh)
    }

    func testALoneOneIsAnsweredWithAThumbsUpAZeroWithAPlea() {
        XCTAssertEqual(suggest(message("1"), all, now: now).first, ok)
        XCTAssertEqual(suggest(message("0"), all, now: now).first, plead)
    }

    func testAnEmojiSentAloneIsEchoed() {
        XCTAssertEqual(suggest(message("", content: .emoji("😂")), all, now: now).first, laugh)
    }

    func testNothingForOnesOwnOldOrNonTextMessages() {
        XCTAssertEqual(suggest(message("haha", mine: true), all, now: now), [])
        XCTAssertEqual(suggest(message("haha", at: day(16, 0)), all, now: now), [])
        XCTAssertEqual(suggest(message("", content: .image(ImageContent(fileId: 1, name: "a", size: 1, time: 1))), all, now: now), [])
        XCTAssertEqual(suggest(nil, all, now: now), [])
    }
}
