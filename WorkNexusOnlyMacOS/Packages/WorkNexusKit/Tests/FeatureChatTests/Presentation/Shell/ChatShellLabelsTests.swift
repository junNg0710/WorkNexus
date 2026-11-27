import CoreDomain
import XCTest
@testable import FeatureChat

final class ChatShellLabelsTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let posix = Locale(identifier: "en_US_POSIX")

    func testTitleOfADirectChatIsThePeerAndFallsBack() {
        let users = [2: ShellMake.user(2, "Bình")]
        XCTAssertEqual(ChatShellLabels.title(ShellMake.chat("d", type: .one2one, peer: 2), users), "Bình")
        XCTAssertEqual(ChatShellLabels.title(ShellMake.chat("d", type: .one2one, peer: 9), users), "User #9")
        XCTAssertEqual(ChatShellLabels.title(ShellMake.chat("g", name: "  Team "), users), "Team")
        XCTAssertEqual(ChatShellLabels.title(ShellMake.chat("g", name: " "), users), "Untitled chat")
        var cloud = ShellMake.chat("c", type: .one2one, peer: 2); cloud.isMyCloud = true
        XCTAssertEqual(ChatShellLabels.title(cloud, users), "My Cloud")
    }

    func testUserNames() {
        let users = [2: ShellMake.user(2, "Bình"), 3: ChatUser(accountId: "a", userId: 3, account: "chi", realname: "")]
        XCTAssertEqual(ChatShellLabels.userName(users, 2), "Bình")
        XCTAssertEqual(ChatShellLabels.userName(users, 3), "chi")
        XCTAssertEqual(ChatShellLabels.userName(users, 0), "Xuanbot")
        XCTAssertEqual(ChatShellLabels.userName(users, 8), "User #8")
    }

    func testInitials() {
        XCTAssertEqual(ChatShellLabels.initials("nguyen van an"), "NV")
        XCTAssertEqual(ChatShellLabels.initials("dev_team"), "DT")
        XCTAssertEqual(ChatShellLabels.initials("An"), "A")
        XCTAssertEqual(ChatShellLabels.initials("  "), "?")
    }

    func testPreviewOfEachContentKind() {
        func p(_ c: MessageContent, reactions: Bool = false, replyTo: Int? = nil) -> String {
            ChatShellLabels.preview(Make.message(content: c, replyTo: replyTo), reactions: reactions)
        }
        XCTAssertEqual(p(.text("hi [@An](@#2)\n  there")), "hi @An there")
        XCTAssertEqual(p(.text("# Title\n- **bold** [link](https://x.y) `code`", markdown: true)), "Title bold link code")
        XCTAssertEqual(p(.text("a ```x = 1``` b", markdown: true)), "a b")
        XCTAssertEqual(p(.emoji("👍")), "👍")
        XCTAssertEqual(p(.image(ImageContent(fileId: 1, name: "a.png", size: 1, time: 1))), "Image")
        XCTAssertEqual(p(.file(FileContent(fileId: 1, name: "spec.pdf", size: 1, time: 1))), "File: spec.pdf")
        XCTAssertEqual(p(.link(url: "https://x.y", title: nil)), "https://x.y")
        XCTAssertEqual(p(.code("let a = 1\nlet b", language: nil, name: nil)), "Code: let a = 1")
        XCTAssertEqual(p(.code("x", language: nil, name: "main.swift")), "Code: main.swift")
        XCTAssertEqual(p(.unsupported("card")), "Unsupported message (card)")
        XCTAssertEqual(p(.emoji("👍"), reactions: true, replyTo: 5), "Reacted 👍")
        XCTAssertEqual(p(.emoji("👍"), reactions: false, replyTo: 5), "👍")
        XCTAssertEqual(ChatShellLabels.preview(Make.message(deleted: true)), "Message retracted")
    }

    func testListTimeIsClockTodayThenYesterdayWeekdayAndDate() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 14:13:20 UTC
        func t(_ days: Double, hours: Double = 0) -> Date { now.addingTimeInterval(-days * 86400 - hours * 3600) }
        func f(_ d: Date?) -> String { ChatShellLabels.listTime(d, now: now, calendar: utc, locale: posix) }
        XCTAssertEqual(f(nil), "")
        XCTAssertEqual(f(t(0, hours: 1)), "13:13")
        XCTAssertEqual(f(t(1)), "Yesterday")
        XCTAssertEqual(f(t(3)), "Fri")
        XCTAssertEqual(f(t(20)), "01/09")
        XCTAssertEqual(f(t(400)), "17/08/25")
    }

    func testTypingLabels() {
        let users = [1: ShellMake.user(1, "An"), 2: ShellMake.user(2, "Bình"), 3: ShellMake.user(3, "Chi"), 4: ShellMake.user(4, "Dũng")]
        XCTAssertEqual(ChatShellLabels.typingLabel(users, []), "")
        XCTAssertEqual(ChatShellLabels.typingLabel(users, [1]), "An is typing…")
        XCTAssertEqual(ChatShellLabels.typingLabel(users, [1, 2]), "An and Bình are typing…")
        XCTAssertEqual(ChatShellLabels.typingLabel(users, [1, 2, 3, 4]), "An and 3 others are typing…")
    }

    func testFileSizesAndBadges() {
        XCTAssertEqual(ChatShellLabels.fileSize(512), "512 B")
        XCTAssertEqual(ChatShellLabels.fileSize(2048), "2 KB")
        XCTAssertEqual(ChatShellLabels.fileSize(3 * 1024 * 1024 + 512 * 1024), "3.5 MB")
        XCTAssertEqual(ChatShellLabels.fileSize(2 * (1 << 30)), "2 GB")
        XCTAssertEqual(ChatShellLabels.fileSize(3 * (1 << 29)), "1.5 GB")
        XCTAssertEqual(ChatShellLabels.fileBadge("report.final.pdf"), "PDF")
        XCTAssertEqual(ChatShellLabels.fileBadge("archive.torrent"), "TORR")
        XCTAssertEqual(ChatShellLabels.fileBadge("README"), "FILE")
        XCTAssertEqual(ChatShellLabels.fileBadge("x."), "FILE")
    }

    func testAttachmentsSplitIntoMediaAndFiles() {
        func file(_ id: Int, _ name: String) -> ChatMessage { Make.message("f\(id)", content: .file(FileContent(fileId: id, name: name, size: 1, time: 1))) }
        let image = Make.message("i", content: .image(ImageContent(fileId: 2, name: "a.png", size: 1, time: 1)))
        let split = ChatShellLabels.splitAttachments([image, file(3, "clip.mp4"), file(4, "doc.pdf"), file(0, "pending.pdf"), Make.message("t")])
        XCTAssertEqual(split.media.map(\.gid), ["i", "f3"])
        XCTAssertEqual(split.files.map(\.gid), ["f4"])
    }

    /// Stickers are reactions, not photos: a sticker-sized WebP / GIF, a Telegram sticker, or a picture named like a
    /// sticker this Mac knows stays out of "Photos & videos". A photo of the same format at full size stays in.
    func testStickersAreLeftOutOfTheSharedPhotos() {
        func image(_ gid: String, _ name: String, _ side: Int?) -> ChatMessage {
            Make.message(gid, content: .image(ImageContent(fileId: 2, name: name, size: 1, time: 1, width: side, height: side)))
        }
        let all = [image("sticker", "053.webp", 512), image("gif", "wave.gif", 240), image("tgs", "hi.tgs", nil), image("mine", "pepe.png", 320),
                   image("photo", "shot.png", 320), image("big", "photo.webp", 1600), image("unknown", "old.webp", nil)]
        let split = ChatShellLabels.splitAttachments(all, stickerNames: ["pepe.png"])
        XCTAssertEqual(split.media.map(\.gid), ["photo", "big", "unknown"])
        XCTAssertTrue(split.files.isEmpty)
        XCTAssertEqual(ChatShellLabels.splitAttachments(all).media.map(\.gid), ["mine", "photo", "big", "unknown"], "no names known: only by format and size")
    }

    func testAvatarStylePerChatKind() {
        let users = [2: ChatUser(accountId: "a", userId: 2, account: "b", realname: "B", avatarUrl: "https://x/b.png")]
        var cloud = ShellMake.chat("c", type: .one2one, peer: 2); cloud.isMyCloud = true
        XCTAssertEqual(ChatShellLabels.avatarStyle(cloud, users).systemIcon, "icloud")
        XCTAssertEqual(ChatShellLabels.avatarStyle(ShellMake.chat("d", type: .one2one, peer: 2), users).imageUrl, "https://x/b.png")
        var group = ShellMake.chat("g", name: "G")
        group.avatarJson = ##"{"type":"text","data":{"customText":"QA","bgColor":"#FF8800"}}"##
        XCTAssertEqual(ChatShellLabels.avatarStyle(group, users), ChatAvatarStyle(label: "QA", background: 0xFF8800))
        group.avatarJson = #"{"type":"image","data":{"imgUrl":"https://x/g.png"}}"#
        XCTAssertEqual(ChatShellLabels.avatarStyle(group, users).imageUrl, "https://x/g.png")
        group.avatarJson = nil
        XCTAssertEqual(ChatShellLabels.avatarStyle(group, users), ChatAvatarStyle())
        XCTAssertNil(ChatShellLabels.hexColor("#12345"))
        XCTAssertEqual(ChatShellLabels.hexColor("00ff7f"), 0x00FF7F)
    }

    func testRoleLabelsAndFilter() {
        XCTAssertEqual(ChatShellLabels.roleLabel("pm"), "Project Manager")
        XCTAssertEqual(ChatShellLabels.roleLabel(" dev "), "Developer")
        XCTAssertEqual(ChatShellLabels.roleLabel("UI"), "Designer")
        XCTAssertEqual(ChatShellLabels.roleLabel("sre", serverNames: ["sre": "Reliability"]), "Reliability")
        XCTAssertEqual(ChatShellLabels.roleLabel("sre"), "sre")
        XCTAssertTrue(ChatShellLabels.roleMatches(nil, "dev"))
        XCTAssertTrue(ChatShellLabels.roleMatches("dev", " dev "))
        XCTAssertTrue(ChatShellLabels.roleMatches("", nil))
        XCTAssertFalse(ChatShellLabels.roleMatches("qa", "dev"))
    }

    func testCertificateText() {
        XCTAssertEqual(ChatShellLabels.certificateName("/C=VN/CN=chat.example.com"), "chat.example.com")
        XCTAssertEqual(ChatShellLabels.certificateName("CN=host name, O=Org"), "host name")
        XCTAssertEqual(ChatShellLabels.certificateName("O=Org"), "O=Org")
        let fp = (0..<20).map { String(format: "%02X", $0) }.joined(separator: ":")
        XCTAssertEqual(ChatShellLabels.fingerprintLines(fp).split(separator: "\n").map { $0.split(separator: ":").count }, [8, 8, 4])
    }

    func testPresenceAndVerifiedBadge() {
        let users = [1: ShellMake.user(1, "A", role: "pm", status: "busy"), 2: ShellMake.user(2, "B", role: "dev", status: "weird")]
        XCTAssertEqual(ChatShellLabels.presence(users, 1), .busy)
        XCTAssertEqual(ChatShellLabels.presence(users, 2), .offline)
        XCTAssertNil(ChatShellLabels.presence(users, 3))
        XCTAssertEqual(ChatShellLabels.verifiedBadge(users, 1)?.rank, .lead)
        XCTAssertNil(ChatShellLabels.verifiedBadge(users, 2))
        XCTAssertEqual(ChatShellLabels.failureText(.expired("x")), "A reaction can only be taken back within 2 minutes")
        XCTAssertEqual(ChatShellLabels.failureText(.network("boom")), "Couldn't complete that: boom")
    }
}
