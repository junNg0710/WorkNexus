import Foundation

/// Not in the Flutter app.
/// A release's notes in the app's language. The notes on GitHub are English, followed by a folded section per translation:
///
///     <details><summary>Tiếng Việt</summary>
///     <!-- lang:vi -->
///     …the whole notes in Vietnamese…
///     </details>
///
/// GitHub shows the English with the translations folded under it; the app shows the translation for its language, else
/// the English without the folded sections. "zh-Hans" matches a "zh" section and the other way round.
public enum LocalizedReleaseNotes {
    private static let section = try! NSRegularExpression(
        pattern: #"<details>\s*<summary>[^<]*</summary>\s*<!--\s*lang:([A-Za-z-]+)\s*-->(.*?)</details>"#,
        options: [.dotMatchesLineSeparators, .caseInsensitive])

    public static func pick(_ notes: String, language: String) -> String {
        let ns = notes as NSString
        let matches = section.matches(in: notes, range: NSRange(location: 0, length: ns.length))
        let wanted = base(language)
        if let hit = matches.first(where: { base(ns.substring(with: $0.range(at: 1))) == wanted }) {
            let text = ns.substring(with: hit.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        var english = notes
        for m in matches.reversed() { english = (english as NSString).replacingCharacters(in: m.range, with: "") }
        return english.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "zh-Hans" → "zh", "vi" → "vi".
    private static func base(_ code: String) -> String {
        String(code.lowercased().split(separator: "-").first ?? "")
    }
}
