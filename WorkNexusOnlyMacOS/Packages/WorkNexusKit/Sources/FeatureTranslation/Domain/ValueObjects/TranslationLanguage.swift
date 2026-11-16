/// Ported from: lib/core/util/translation_languages.dart
/// The languages a ticket can be machine-translated into. To offer another target, add one entry here.
public struct TranslationLanguage: Sendable, Equatable, Identifiable {
    /// BCP-47 primary subtag persisted with the translation + settings (`vi`).
    public let code: String
    /// English name fed to the model prompt (`Vietnamese`).
    public let englishName: String
    /// Endonym shown in the UI (`Tiếng Việt`).
    public let nativeName: String
    /// Flag emoji shown in the picker and the translation tab.
    public let flag: String
    public var id: String { code }
}

/// Default target language — Vietnamese, per the app's ZenTao-first audience.
public let defaultTranslationLang = "vi"

public let translationLanguages: [TranslationLanguage] = [
    TranslationLanguage(code: "vi", englishName: "Vietnamese", nativeName: "Tiếng Việt", flag: "🇻🇳"),
    TranslationLanguage(code: "en", englishName: "English", nativeName: "English", flag: "🇬🇧"),
    TranslationLanguage(code: "ja", englishName: "Japanese", nativeName: "日本語", flag: "🇯🇵"),
    TranslationLanguage(code: "zh", englishName: "Chinese (Simplified)", nativeName: "中文", flag: "🇨🇳"),
    TranslationLanguage(code: "ko", englishName: "Korean", nativeName: "한국어", flag: "🇰🇷"),
]

/// Resolves a language `code` to its descriptor, falling back to the default (first entry) for an unknown/legacy code.
public func translationLanguage(for code: String) -> TranslationLanguage {
    translationLanguages.first { $0.code == code } ?? translationLanguages[0]
}
