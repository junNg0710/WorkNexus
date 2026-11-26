import CoreDomain
import Foundation

// Not in the Flutter app.

extension ZenTaoAction {
    /// The files attached to this history entry (`actions[i].files`: a list, or an id-keyed object), in upload order.
    var files: [ZenTaoFile] {
        listOrMapValues(json["files"]).compactMap(asMap)
            .sorted { (zentaoInt($0["id"]) ?? 0) < (zentaoInt($1["id"]) ?? 0) }
            .map(ZenTaoFile.init(json:))
    }
}

/// The extensions shown as a picture in a comment; any other file is a link.
private let commentPictureExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic"]

/// A comment as the app shows it: its text, then the files attached to it - a picture as a picture, any other file as a
/// link under its name. ZenTao keeps what is attached to a comment apart from its text (`actions[i].files`), so a
/// comment of two words and a screenshot showed as the two words alone.
func zentaoCommentBody(_ action: ZenTaoAction, baseUrl: String) -> String {
    let parts = zentaoAttachments(action.files, baseUrl: baseUrl).map { file -> String in
        let url = htmlEscaped(file.url), title = htmlEscaped(file.title)
        return commentPictureExtensions.contains(file.extension ?? "")
            ? "<p><img src=\"\(url)\" alt=\"\(title)\" /></p>"
            : "<p><a href=\"\(url)\">\(title)</a></p>"
    }
    return action.commentText + parts.joined()
}

/// The names of the files attached to a history entry that is not a comment (a resolve or reopen with a file), for its
/// row: those ZenTao names in the note's "Added Files" line, then the entry's own, each once.
func zentaoActivityFileNames(_ action: ZenTaoAction, noted: [String], baseUrl: String) -> [String] {
    var names = noted
    for file in zentaoAttachments(action.files, baseUrl: baseUrl) where !names.contains(file.title) { names.append(file.title) }
    return names
}

private func htmlEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}
