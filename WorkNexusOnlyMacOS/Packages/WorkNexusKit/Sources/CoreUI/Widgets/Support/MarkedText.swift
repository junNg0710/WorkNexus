/// Not in the Flutter app.
import CoreDomain
import Foundation

public extension AttributedString {
    /// Sets `attributes` on every place one of `terms` is found in the text - the words of a search, compared without
    /// case or diacritics (`SearchTerms`). Nothing changes without terms.
    mutating func mark(_ terms: [String], with attributes: AttributeContainer) {
        guard !terms.isEmpty else { return }
        let plain = String(characters)
        for found in SearchTerms.ranges(of: terms, in: plain) {
            guard let range = Range(found, in: self) else { continue }
            self[range].mergeAttributes(attributes)
        }
    }

    /// `text` with the places `terms` are found given `attributes`.
    static func marked(_ text: String, _ terms: [String], with attributes: AttributeContainer) -> AttributedString {
        var out = AttributedString(text)
        out.mark(terms, with: attributes)
        return out
    }
}
