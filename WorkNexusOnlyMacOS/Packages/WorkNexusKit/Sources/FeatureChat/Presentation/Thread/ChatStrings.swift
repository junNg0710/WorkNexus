/// Ported from: lib/l10n/app_en.arb (the chat keys the thread uses)
import CoreUI
import Foundation

/// The thread's UI strings, by their `lib/l10n/*.arb` key. Plural forms are resolved here (`{count, plural, …}`).
enum L {
    private static func fill(_ key: String, _ fallback: String, _ args: [String: String]) -> String {
        shellString(key, fallback, args)
    }
    private static func plural(_ key: String, one: String, other: String, _ count: Int) -> String {
        fill(key, count == 1 ? one : other, ["count": "\(count)"])
    }

    static var you: String { appString("chatYou", "You") }
    static var retracted: String { appString("chatRetracted", "Message retracted") }
    static func unsupported(_ type: String) -> String { fill("chatUnsupportedMessage", "Unsupported message ({type})", ["type": type]) }
    static var uploading: String { appString("chatUploading", "Uploading…") }
    static var sending: String { appString("chatSending", "Sending…") }
    static var sendFailed: String { appString("chatSendFailed", "Not sent · Retry") }
    static func replies(_ n: Int) -> String { plural("chatReplies", one: "1 reply", other: "\(n) replies", n) }
    static var replyMissing: String { appString("chatReplyMissing", "Original message not loaded") }
    static var translating: String { appString("chatTranslating", "Translating…") }
    static func translateFailed(_ e: String) -> String { fill("chatTranslateFailed", "Translation failed: {error}", ["error": e]) }
    static func translatedBy(_ m: String) -> String { fill("chatTranslatedBy", "Translated by {model}", ["model": m]) }
    static var beginning: String { appString("chatBeginning", "Start of the conversation") }
    static var loadOlder: String { appString("chatLoadOlder", "Load earlier messages") }
    static var noMessages: String { appString("chatNoMessages", "No messages yet") }
    static func newMessages(_ n: Int) -> String { plural("chatNewMessages", one: "1 new message", other: "\(n) new messages", n) }
    static var scrollToLatest: String { appString("chatScrollToLatest", "Jump to the latest message") }
    static var today: String { appString("chatToday", "Today") }
    static var yesterday: String { appString("chatYesterday", "Yesterday") }
    static var reply: String { appString("chatReply", "Reply") }
    static var openThread: String { appString("chatOpenThread", "Open thread") }
    static var forward: String { appString("chatForward", "Forward") }
    static var copy: String { appString("chatCopy", "Copy text") }
    static var copied: String { appString("chatCopied", "Copied") }
    static var hideTranslation: String { appString("chatShowOriginal", "Hide translation") }
    static var translate: String { appString("chatTranslate", "Translate") }
    static var retranslate: String { appString("chatRetranslate", "Translate again") }
    static var saveSticker: String { appString("chatSaveSticker", "Save as sticker") }
    static var pin: String { appString("chatPin", "Pin") }
    static var unpin: String { appString("chatUnpin", "Unpin") }
    static var retract: String { appString("chatRetract", "Retract") }
    static var react: String { appString("chatReact", "React") }
    static var reactMore: String { appString("chatReactMore", "More emoji") }
    static var moreActions: String { appString("chatMoreActions", "More") }
    static func reactionBy(_ names: String, _ emoji: String) -> String { fill("chatReactionBy", "{names} reacted with {emoji}", ["names": names, "emoji": emoji]) }
    static var mrLoading: String { appString("chatMrLoading", "Loading status…") }
    static func mrNoAccount(_ host: String) -> String { fill("chatMrNoAccount", "Connect an account for {host} to see its status", ["host": host]) }
    static var mrUnavailable: String { appString("chatMrUnavailable", "Status unavailable — tap to open") }
    static func mrFiles(_ n: Int) -> String { plural("chatMrFiles", one: "1 file", other: "\(n) files", n) }
    static var botName: String { appString("chatBotName", "Xuanbot") }
    static func unknownUser(_ id: Int) -> String { fill("chatUnknownUser", "User #{id}", ["id": "\(id)"]) }
    static var jumpNotFound: String { appString("chatJumpNotFound", "Original message not found") }
    static var image: String { appString("chatImage", "Image") }
    static var file: String { appString("chatFile", "File") }
    static var code: String { appString("chatCode", "Code") }
    static func reacted(_ e: String) -> String { fill("chatReacted", "Reacted {emoji}", ["emoji": e]) }
    static func typingOne(_ n: String) -> String { fill("chatTypingOne", "{name} is typing…", ["name": n]) }
    static func typingTwo(_ a: String, _ b: String) -> String { fill("chatTypingTwo", "{first} and {second} are typing…", ["first": a, "second": b]) }
    static func typingMany(_ n: String, _ c: Int) -> String { fill("chatTypingMany", "{name} and {count} others are typing…", ["name": n, "count": "\(c)"]) }
    static var pinnedBarTitle: String { appString("chatPinnedBarTitle", "Message") }
    static func morePins(_ n: Int) -> String { fill("chatMorePins", "+{count} pinned", ["count": "\(n)"]) }
    static var viewOriginal: String { appString("chatViewOriginal", "View original message") }
    static var justNow: String { appString("justNow", "just now") }
    static func minutesAgo(_ n: Int) -> String { fill("minutesAgo", "{count}m ago", ["count": "\(n)"]) }
    static func hoursAgo(_ n: Int) -> String { fill("hoursAgo", "{count}h ago", ["count": "\(n)"]) }
    static func daysAgo(_ n: Int) -> String { fill("daysAgo", "{count}d ago", ["count": "\(n)"]) }
    static var failedToLoad: String { appString("chatLoadFailed", "Could not load messages") }
}
