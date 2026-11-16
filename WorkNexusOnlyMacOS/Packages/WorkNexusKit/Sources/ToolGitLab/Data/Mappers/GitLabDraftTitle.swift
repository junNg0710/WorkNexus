import Foundation

/// Ported from: lib/tools/gitlab/data/mappers/gitlab_draft_title.dart
/// GitLab marks a merge request as a draft by a title prefix (the REST update endpoint has no `draft` flag), so
/// toggling it means editing the title. The prefixes are the ones GitLab itself recognizes.
private let draftPrefix = try! NSRegularExpression(
    pattern: #"^\s*(\[draft\]|\(draft\)|draft:|draft\s+-|\[wip\]|wip:)\s*"#, options: [.caseInsensitive])

/// `title` with any draft prefix removed ("Draft: Fix x" → "Fix x").
func readyTitle(_ title: String) -> String {
    var out = title
    while true {
        let range = NSRange(out.startIndex..., in: out)
        guard let m = draftPrefix.firstMatch(in: out, options: [], range: range), let r = Range(m.range, in: out) else { return out }
        out.removeSubrange(r)
    }
}

/// `title` carrying GitLab's canonical draft prefix, exactly once.
func draftTitle(_ title: String) -> String { "Draft: \(readyTitle(title))" }
