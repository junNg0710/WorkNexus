/// Not in the Flutter app.
import Foundation

/// The pictures of a rich text, named the way ZenTao's own editor names them.
///
/// A picture put into a text is uploaded first (`file-ajaxUpload-<uid>`), and ZenTao answers the link to read it at, a
/// path under its web root (`/zentao/file-read-31.png`). When the text is saved, ZenTao looks for exactly that link in
/// it: a picture it finds is kept (the link becomes `{31.png}`), and every other picture uploaded under the same `uid`
/// is deleted from the server as unused. The app shows the picture from its absolute URL, and saved the text with that
/// URL in it - which ZenTao does not recognise: the bug was created, and its picture's file was gone
/// ("未找到该文件，可能物理文件已被删除"). So, on the way out, the server's own origin is taken off those links again.
func zentaoOwnImageLinks(_ html: String, baseUrl: String) -> String {
    guard html.contains("file-read-") || html.contains("f=read"),
          let base = URLComponents(string: baseUrl), let scheme = base.scheme, let host = base.host else { return html }
    let origin = "\(scheme)://\(host)" + (base.port.map { ":\($0)" } ?? "")
    let pattern = "(\\ssrc=[\"'])" + NSRegularExpression.escapedPattern(for: origin)
        + "(/[^\"'<>]*(?:file-read-[0-9]+|[?&](?:amp;)?f=read)[^\"'<>]*[\"'])"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return html }
    return regex.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "$1$2")
}

extension ZenTaoForm {
    /// The form with every text field passed through `change`.
    func mappingText(_ change: (String) -> String) -> ZenTaoForm {
        var out = self
        for (key, value) in items { if case .text(let text) = value { out.set(key, .text(change(text))) } }
        return out
    }
}

extension ZenTaoBody {
    /// The body with the pictures of its texts named as ZenTao names them (`zentaoOwnImageLinks`).
    func withOwnImageLinks(baseUrl: String) -> ZenTaoBody {
        switch self {
        case .form(let form): return .form(form.mappingText { zentaoOwnImageLinks($0, baseUrl: baseUrl) })
        case .multipart(let fields, let files):
            return .multipart(fields: fields.mappingText { zentaoOwnImageLinks($0, baseUrl: baseUrl) }, files: files)
        case .json: return self
        }
    }
}
