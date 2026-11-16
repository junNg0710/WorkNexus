import Foundation

/// Small helpers over `NSRegularExpression` so the ported Dart regexes (which use `allMatches` /
/// `replaceAllMapped`) stay close to their source. ICU syntax is a superset of what the Dart code uses.
struct RxMatch {
    let source: NSString
    let result: NSTextCheckingResult

    /// Capture group `i` (0 = whole match); nil when the group did not take part.
    subscript(_ i: Int) -> String? {
        let r = result.range(at: i)
        return r.location == NSNotFound ? nil : source.substring(with: r)
    }
    func named(_ name: String) -> String? {
        let r = result.range(withName: name)
        return r.location == NSNotFound ? nil : source.substring(with: r)
    }
    var range: NSRange { result.range }
}

extension NSRegularExpression {
    convenience init(_ pattern: String, options: NSRegularExpression.Options = []) {
        // Patterns are compile-time constants; a failure is a programmer error.
        try! self.init(pattern: pattern, options: options)
    }

    func matches(in text: String) -> [RxMatch] {
        let ns = text as NSString
        return matches(in: text, range: NSRange(location: 0, length: ns.length)).map { RxMatch(source: ns, result: $0) }
    }

    func firstMatch(in text: String) -> RxMatch? {
        let ns = text as NSString
        return firstMatch(in: text, range: NSRange(location: 0, length: ns.length)).map { RxMatch(source: ns, result: $0) }
    }

    func hasMatch(in text: String) -> Bool { firstMatch(in: text) != nil }

    /// Dart's `replaceAllMapped`.
    func replacing(in text: String, _ transform: (RxMatch) -> String) -> String {
        let ns = text as NSString
        var out = ""
        var at = 0
        for m in matches(in: text) {
            out += ns.substring(with: NSRange(location: at, length: m.range.location - at))
            out += transform(m)
            at = m.range.location + m.range.length
        }
        out += ns.substring(from: at)
        return out
    }
}
