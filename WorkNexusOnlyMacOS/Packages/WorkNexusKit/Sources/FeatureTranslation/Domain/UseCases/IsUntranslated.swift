import Foundation

/// Not in the Flutter app.
/// Whether a translation into `targetLang` is still mostly Chinese / Japanese / Korean: a model sometimes rewrites a CJK
/// ticket in its own language instead of translating it, and that must not be kept (or shown) as a translation. A target
/// that is itself CJK is never flagged; HTML tags and attributes are left out of the count.
public struct IsUntranslated: Sendable {
    public init() {}

    /// The share of letters that may be CJK before a non-CJK translation counts as untranslated.
    static let cjkShare = 0.3

    public func callAsFunction(_ text: String, targetLang: String) -> Bool {
        let lang = targetLang.lowercased()
        if ["zh", "ja", "ko"].contains(where: { lang == $0 || lang.hasPrefix($0 + "-") || lang.hasPrefix($0 + "_") }) { return false }
        let visible = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        var letters = 0, cjk = 0
        for scalar in visible.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if Self.isCJK(scalar) { cjk += 1 }
        }
        return letters > 0 && Double(cjk) / Double(letters) > Self.cjkShare
    }

    public func callAsFunction(_ record: TranslationRecord) -> Bool {
        callAsFunction(record.translatedTitle + "\n" + record.translatedBody, targetLang: record.targetLang)
    }

    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: true   // Han
        case 0x3040...0x30FF, 0x31F0...0x31FF: true                                    // Hiragana, Katakana
        case 0xAC00...0xD7AF, 0x1100...0x11FF: true                                    // Hangul
        default: false
        }
    }
}
