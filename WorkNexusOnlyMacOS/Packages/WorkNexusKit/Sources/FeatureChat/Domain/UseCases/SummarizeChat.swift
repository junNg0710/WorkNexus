import CoreDomain
import Foundation

/// Summarizes chat messages for someone catching up: an overview, the key points, decisions, action items and open questions,
/// written in `languageName` (the app's language, or the one picked) whatever language the chat is in.
/// Ported from: lib/features/chat/domain/usecases/summarize_chat.dart
public struct SummarizeChat: Sendable {
    private let generator: ChatAiTextGenerator
    public var transcript: BuildChatTranscript
    public init(_ generator: ChatAiTextGenerator, transcript: BuildChatTranscript = BuildChatTranscript()) {
        self.generator = generator; self.transcript = transcript
    }

    public func callAsFunction(_ messages: [ChatMessage], key: String, languageName: String, selfName: String,
                               nameOf: (Int) -> String, model: String? = nil) async -> Outcome<ChatSummary> {
        let quoted = transcript(messages, nameOf: nameOf, selfName: selfName)
        guard quoted.count > 0 else { return .failure(.unexpected("There are no messages to summarize")) }
        let reply = await generator.generate(key: key, prompt: Self.prompt(quoted.text, count: quoted.count, languageName: languageName),
                                             model: model)
        return reply.map { Self.parse($0, count: quoted.count) }
    }

    /// The model's answer as a summary. One that is not the JSON asked for is still worth reading, so it becomes the overview
    /// as written.
    public static func parse(_ answer: ChatAiReply, count: Int) -> ChatSummary {
        guard let json = ExtractAiJson.extract(answer.text) as? [String: Any] else {
            return ChatSummary(overview: answer.text.trimmingCharacters(in: .whitespacesAndNewlines), messageCount: count, model: answer.model)
        }
        func trimmed(_ value: Any?) -> String { ExtractAiJson.text(value)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        let items: [ChatActionItem] = ((json["actionItems"] as? [Any]) ?? []).compactMap { item in
            guard let fields = item as? [String: Any], let task = fields["task"] as? String,
                  !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return ChatActionItem(task: trimmed(task), owner: trimmed(fields["owner"]), due: trimmed(fields["due"]))
        }
        return ChatSummary(overview: trimmed(json["overview"]), keyPoints: ExtractAiJson.strings(json["keyPoints"]),
                           decisions: ExtractAiJson.strings(json["decisions"]), actionItems: items,
                           openQuestions: ExtractAiJson.strings(json["openQuestions"]), messageCount: count, model: answer.model)
    }

    public static func prompt(_ transcript: String, count: Int, languageName: String) -> String {
        "You are an assistant in a team chat app. Summarize the conversation below for a teammate who is catching up on it.\n"
            + "Write in \(languageName). Be concise and factual: use only what the messages say. Keep names, ticket ids, numbers, "
            + "links and code as written.\n"
            + "Return ONLY a JSON object with these keys:\n"
            + "\"overview\": 1-3 sentences on what the conversation is about and where it stands;\n"
            + "\"keyPoints\": the most important points, at most 6 short strings;\n"
            + "\"decisions\": decisions that were made (an empty list when none);\n"
            + "\"actionItems\": things someone is to do, as objects {\"owner\": who, or \"\", \"task\": what, \"due\": when, or \"\"} "
            + "(an empty list when none);\n"
            + "\"openQuestions\": questions still unanswered (an empty list when none).\n"
            + "Conversation (\(count) messages, oldest first):\n"
            + "<<<\n\(transcript)\n>>>"
    }
}

/// Whether opening a chat offers to summarize what came in meanwhile: only when there is more than a quick scroll's worth of
/// unread messages.
/// Ported from: lib/features/chat/domain/usecases/should_offer_chat_summary.dart
public struct ShouldOfferChatSummary: Sendable {
    /// The fewest unread messages worth a summary.
    public var threshold: Int
    public init(threshold: Int = 20) { self.threshold = threshold }
    public func callAsFunction(unread: Int) -> Bool { unread >= threshold }
}

/// The language a summary is written in: the one picked, else the app's, out of the languages offered (the first of them
/// when neither is offered).
/// Ported from: lib/features/chat/presentation/widgets/chat_ai_actions.dart (`chatSummaryLanguageCode`) +
/// lib/core/util/translation_languages.dart (`translationLanguageFor`)
public struct ResolveChatSummaryLanguage: Sendable {
    public init() {}
    public func callAsFunction(picked: String?, appLanguage: String, offered: [ChatAiLanguage]) -> ChatAiLanguage {
        let code = picked ?? appLanguage
        return offered.first { $0.code == code } ?? offered.first
            ?? ChatAiLanguage(code: "en", englishName: "English", nativeName: "English", flag: "🇬🇧")
    }
}
