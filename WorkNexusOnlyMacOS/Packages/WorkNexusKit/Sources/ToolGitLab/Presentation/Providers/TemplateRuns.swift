import Foundation

/// Ported from: lib/tools/gitlab/presentation/util/template_runs.dart
/// One run of a localized sentence: literal `text`, or the placeholder at index `slot`.
struct TemplateRun: Equatable { var text: String; var slot: Int? }

/// Splits a localized message around its placeholders, so each one can render as its own span or view (a bold name, a
/// branch ref) while translators keep control of the word order. `build` gets one marker per placeholder — in
/// placeholder order — and returns the message built from them.
func templateRuns(slots: Int, _ build: ([String]) -> String) -> [TemplateRun] {
    // Private-use code points never occur in real text.
    let marks = (0..<slots).map { String(UnicodeScalar(0xE000 + $0)!) }
    var runs: [TemplateRun] = []
    var literal = ""
    for ch in build(marks) {
        if let i = marks.firstIndex(of: String(ch)) {
            if !literal.isEmpty { runs.append(TemplateRun(text: literal, slot: nil)); literal = "" }
            runs.append(TemplateRun(text: String(ch), slot: i))
        } else { literal.append(ch) }
    }
    if !literal.isEmpty { runs.append(TemplateRun(text: literal, slot: nil)) }
    return runs
}
