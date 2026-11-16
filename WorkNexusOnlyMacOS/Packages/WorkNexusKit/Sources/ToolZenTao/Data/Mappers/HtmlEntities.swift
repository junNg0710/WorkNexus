import Foundation

/// Ported from: lib/core/util/html_entities.dart, lib/core/util/content_hash.dart
/// Replaces HTML character references - named (`&quot;`, `&amp;`, ...) and numeric (`&#39;`, `&#x2F;`) - with
/// the characters they stand for. ZenTao returns titles HTML-escaped; unknown names are left as written.
func decodeHtmlEntities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    let named = ["quot": "\"", "amp": "&", "lt": "<", "gt": ">", "apos": "'", "nbsp": " "]
    let ns = text as NSString
    var out = ""
    var last = 0
    for m in htmlReference.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        last = m.range.location + m.range.length
        let whole = ns.substring(with: m.range)
        func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        if let name = group(1) {
            out += named[name] ?? whole
        } else {
            let code: UInt32? = group(2).flatMap { UInt32($0, radix: 16) } ?? group(3).flatMap { UInt32($0) }
            if let code, code > 0, code <= 0x10FFFF, let scalar = Unicode.Scalar(code) { out.unicodeScalars.append(scalar) } else { out += whole }
        }
    }
    out += ns.substring(from: last)
    return out
}

private let htmlReference = try! NSRegularExpression(pattern: "&(?:([a-zA-Z]+)|#[xX]([0-9a-fA-F]{1,6})|#([0-9]{1,7}));")

/// Stable non-negative 31-bit hash of a string (h*31+c over UTF-16 code units).
func intHash(_ s: String) -> Int {
    var h = 0
    for c in s.utf16 { h = ((h &* 31) &+ Int(c)) & 0x7fff_ffff }
    return h
}

/// Stable, deterministic content hash keying translation caches and detecting when a ticket's text changed.
func contentHash(_ title: String, _ body: String) -> String { String(intHash("\(title) \(body)"), radix: 16) }

extension String {
    /// Dart `RegExp(pattern).hasMatch(this)`.
    func matches(_ pattern: String) -> Bool { range(of: pattern, options: .regularExpression) != nil }

    /// Replaces every match of a regular expression with `template` (`$1` groups allowed).
    func replacingRegex(_ pattern: String, with template: String, options: NSRegularExpression.Options = []) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return self }
        return re.stringByReplacingMatches(in: self, range: NSRange(location: 0, length: (self as NSString).length), withTemplate: template)
    }
}
