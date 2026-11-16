import Foundation

/// Thin NSRegularExpression wrapper with Dart-like `RegExp` ergonomics (UTF-16 offsets, numbered groups).
struct RX {
    let re: NSRegularExpression
    init(_ pattern: String, caseInsensitive: Bool = false) {
        re = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    struct Match {
        let result: NSTextCheckingResult
        let ns: NSString
        subscript(i: Int) -> String? {
            let r = result.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        var range: NSRange { result.range }
        var start: Int { result.range.location }
        var end: Int { result.range.location + result.range.length }
        var whole: String { ns.substring(with: result.range) }
    }

    func matches(_ s: String) -> [Match] {
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { Match(result: $0, ns: ns) }
    }
    func first(_ s: String) -> Match? {
        let ns = s as NSString
        return re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)).map { Match(result: $0, ns: ns) }
    }
    func hasMatch(_ s: String) -> Bool { first(s) != nil }
    func isFullMatch(_ s: String) -> Bool {
        guard let m = first(s) else { return false }
        return m.range.location == 0 && m.range.length == (s as NSString).length
    }

    /// `replaceAllMapped`.
    func replace(_ s: String, _ f: (Match) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var at = 0
        for m in matches(s) {
            out += ns.substring(with: NSRange(location: at, length: m.start - at))
            out += f(m)
            at = m.end
        }
        out += ns.substring(from: at)
        return out
    }
}
