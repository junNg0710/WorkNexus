import CoreDomain
import Foundation

/// What the model answered, and which model did (nil when the backend used its own default without naming it).
/// Ported from: lib/features/chat/domain/repositories/chat_ai_text_generator.dart
public struct ChatAiReply: Hashable, Sendable {
    public var text: String
    public var model: String?
    public init(_ text: String, model: String? = nil) { self.text = text; self.model = model }
}

/// Answers a free-form prompt with the AI backend the user set up for translation (OpenCode, or their own API key), so the
/// chat's AI features need no setup of their own. Implemented by the composition root over the translation feature.
/// Ported from: lib/features/chat/domain/repositories/chat_ai_text_generator.dart
public protocol ChatAiTextGenerator: Sendable {
    /// Answers `prompt`; `key` names the run so `cancel` can stop it. `model` pins the model, nil leaves it to the backend.
    func generate(key: String, prompt: String, model: String?) async -> Outcome<ChatAiReply>
    /// Stops the run named `key`; its `generate` then completes with a failure.
    func cancel(_ key: String) async
}

/// A language an AI summary can be written in (the translation languages, handed over by the host).
/// Ported from: lib/core/util/translation_languages.dart (`TranslationLanguage`)
public struct ChatAiLanguage: Hashable, Sendable {
    public var code: String
    /// The name the prompt uses (`Vietnamese`).
    public var englishName: String
    /// The name the picker shows (`Tiếng Việt`).
    public var nativeName: String
    public var flag: String
    public init(code: String, englishName: String, nativeName: String, flag: String) {
        self.code = code; self.englishName = englishName; self.nativeName = nativeName; self.flag = flag
    }
}

/// Who is who for a prompt: the user's own name and everyone else's by user id.
/// Ported from: lib/features/chat/presentation/providers/chat_ai_providers.dart (`chatAiPeopleProvider`)
public struct ChatAiPeople: Sendable {
    public var selfName: String
    private var names: [Int: String]

    /// - Parameter roleOf: when given, each person's name carries their role in brackets (`Lan (QA tester)`), so reply
    ///   ideas can tell who is asking what; summaries leave it out.
    public init(users: [Int: ChatUser], selfUserId: Int?, roleOf: ((ChatUser) -> String?)? = nil) {
        let own = selfUserId.flatMap { users[$0]?.realname } ?? ""
        selfName = own.isEmpty ? "Me" : own
        names = users.compactMapValues { u in
            guard !u.realname.isEmpty else { return nil }
            guard let role = roleOf?(u), !role.isEmpty else { return u.realname }
            return "\(u.realname) (\(role))"
        }
    }

    public func name(of userId: Int) -> String { names[userId] ?? "User \(userId)" }
}
