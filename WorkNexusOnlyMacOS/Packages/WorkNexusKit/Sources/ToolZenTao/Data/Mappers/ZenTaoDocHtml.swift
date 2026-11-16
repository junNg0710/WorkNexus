import Foundation

/// Ported from: lib/tools/zentao/data/mappers/zentao_doc_html.dart
/// Cleans the HTML ZenTao 21's block editor exports for a document, which carries editor artefacts that read as
/// noise outside its web page:
/// - `<pre>` boxes pinned to a white background (`style="background-color:#FFFFFF"`);
/// - tables opened by an empty header row (`<th></th><th></th>`) when the author used a plain key/value grid;
/// - empty paragraphs left between blocks, each a full blank line.
func tidyZenTaoDocHtml(_ html: String) -> String {
    if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return html }
    let fragment = HNode.parseFragment(html)
    for pre in fragment.elements("pre") { pre.removeAttribute("style") }
    for tag in ["thead", "tr", "p"] {
        for e in fragment.elements(tag) where isBlank(e) { e.remove() }
    }
    return fragment.innerHtml
}

private func isBlank(_ e: HNode) -> Bool {
    e.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && e.firstElement("img") == nil
}
