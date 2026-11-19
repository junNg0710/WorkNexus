import CoreDomain
import Foundation

/// Proposes a few short replies the user could send next, in the language and tone the chat uses, from its latest messages.
/// They are only suggestions: the user picks one into the composer and edits it before sending.
/// Ported from: lib/features/chat/domain/usecases/suggest_chat_replies.dart
public struct SuggestChatReplies: Sendable {
    private let generator: ChatAiTextGenerator
    public var transcript: BuildChatTranscript
    /// How many replies are asked for (and kept at most).
    public var count: Int
    public init(_ generator: ChatAiTextGenerator, transcript: BuildChatTranscript = BuildChatTranscript(maxChars: 6000), count: Int = 3) {
        self.generator = generator; self.transcript = transcript; self.count = count
    }

    /// - Parameter selfRole: how the user writes in the team (`ResolveReplyRole`); nil leaves the voice to the conversation.
    public func callAsFunction(_ messages: [ChatMessage], key: String, selfName: String, nameOf: (Int) -> String,
                               selfRole: String? = nil, model: String? = nil) async -> Outcome<[String]> {
        let quoted = transcript(messages, nameOf: nameOf, selfName: selfName)
        guard quoted.count > 0 else { return .failure(.unexpected("There is nothing to reply to yet")) }
        let prompt = Self.prompt(quoted.text, selfName: selfName, count: count, selfRole: selfRole)
        let reply = await generator.generate(key: key, prompt: prompt, model: model)
        return reply.flatMap { answer in
            let replies = Self.parse(answer.text, count: count)
            return replies.isEmpty ? .failure(.parse("The model suggested no replies")) : .success(replies)
        }
    }

    private static let numbering = RX(#"^(\d+[.)]|[-*•])\s*"#)
    private static let quotes = RX(#"^["'“”]+|["'“”]+$"#)

    /// The replies in the model's answer: the JSON list asked for, else one a line with any numbering or bullet taken off.
    public static func parse(_ answer: String, count: Int) -> [String] {
        let json = ExtractAiJson.extract(answer, array: true)
        let replies: [String] = json is [Any]
            ? ExtractAiJson.strings(json)
            : answer.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                .map { numbering.replace($0) { _ in "" } }
        return replies.prefix(count).map { quotes.replace($0) { _ in "" }.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func prompt(_ transcript: String, selfName: String, count: Int, selfRole: String? = nil) -> String {
        let role = selfRole.map {
            "\(selfName) is \($0). Write every reply the way someone in that role would: what they would say, decide, ask or "
                + "report next, with the details that role cares about.\n"
                + "A name in the conversation may carry that person's role in brackets; use it to judge what they need from "
                + "\(selfName) (a tester reporting a bug, a lead asking for status, …).\n"
        } ?? ""
        return "You help \(selfName) answer in a team chat. Read the latest messages and write \(count) different short replies "
            + "\(selfName) could send next.\n"
            + role
            + "Lines from \"\(selfName)\" are \(selfName)'s own messages. When the last message is \(selfName)'s own, write "
            + "follow-ups \(selfName) could add, not answers to it.\n"
            + "Use the language the conversation is written in, and match its tone. Be natural, specific and brief (under 25 "
            + "words each). Make them differ (for example: agree, ask a follow-up question, give a status).\n"
            + "Plain text only: no Markdown, no quotes, no sender names.\n"
            + "Return ONLY a JSON array of \(count) strings.\n"
            + "Conversation (oldest first):\n"
            + "<<<\n\(transcript)\n>>>"
    }
}

/// Rewrites what the user is typing in a `ChatDraftTone`, keeping its meaning and language. The latest messages are given as
/// context only, so the rewrite fits the conversation without answering it.
/// Ported from: lib/features/chat/domain/usecases/rewrite_chat_draft.dart
public struct RewriteChatDraft: Sendable {
    private let generator: ChatAiTextGenerator
    public var transcript: BuildChatTranscript
    public init(_ generator: ChatAiTextGenerator, transcript: BuildChatTranscript = BuildChatTranscript(maxChars: 3000)) {
        self.generator = generator; self.transcript = transcript
    }

    public func callAsFunction(_ draft: String, tone: ChatDraftTone, key: String, context: [ChatMessage] = [], selfName: String = "",
                               nameOf: ((Int) -> String)? = nil, model: String? = nil) async -> Outcome<String> {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.unexpected("There is nothing to rewrite")) }
        let quoted = nameOf.map { transcript(context, nameOf: $0, selfName: selfName).text }
        let reply = await generator.generate(key: key, prompt: Self.prompt(draft, tone: tone, context: quoted), model: model)
        return reply.flatMap { answer in
            let text = Self.unwrap(answer.text)
            return text.isEmpty ? .failure(.parse("The model returned no text")) : .success(text)
        }
    }

    private static let fenceOpen = RX(#"^```\w*\s*"#), fenceClose = RX(#"\s*```$"#), quotes = RX(#"^["“]+|["”]+$"#)

    /// The rewrite without the quotes or code fence a model may put around it.
    static func unwrap(_ answer: String) -> String {
        var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = fenceOpen.first(text) { text = String((text as NSString).substring(from: m.end)) }
        if let m = fenceClose.first(text) { text = String((text as NSString).substring(to: m.start)) }
        return quotes.replace(text) { _ in "" }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func prompt(_ draft: String, tone: ChatDraftTone, context: String?) -> String {
        let how = switch tone {
        case .clearer: "so it is clear and well written, fixing grammar and spelling"
        case .formal: "in a polite, professional tone"
        case .friendly: "in a warm, friendly tone"
        case .shorter: "to be shorter and to the point"
        }
        let background = (context ?? "").isEmpty ? "" : "The latest messages, for context only (do not answer them):\n<<<\n\(context!)\n>>>\n"
        return "Rewrite this chat message draft \(how). Keep its meaning and the language it is written in; keep @mentions, "
            + "links, code and emoji as they are.\n"
            + "Return ONLY the rewritten message, with no preface or quotes.\n"
            + background
            + "Draft:\n<<<\n\(draft)\n>>>"
    }
}
