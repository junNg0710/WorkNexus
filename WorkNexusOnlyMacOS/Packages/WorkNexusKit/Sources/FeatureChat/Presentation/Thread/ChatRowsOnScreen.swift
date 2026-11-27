/// Not in the Flutter app.
import CoreDomain
import Foundation

/// What the performance log says about the chat rows on screen when it notes a stutter: how many, and how many of the
/// kinds that cost the most to draw.
enum ChatRowsOnScreen {
    static func describe(_ rows: [ChatListRow], visible: Set<String>) -> String {
        var count = 0, pictures = 0, stickers = 0, videos = 0, files = 0, links = 0, long = 0, code = 0
        for row in rows where visible.contains(row.id) {
            count += 1
            guard case .message(let m) = row.item else { continue }
            switch m.content {
            case .image(let i): if IsStickerImage()(i) { stickers += 1 } else { pictures += 1 }
            case .file(let f): if isVideoFile(f) { videos += 1 } else { files += 1 }
            case .text(let t, _):
                if t.contains("http://") || t.contains("https://") { links += 1 }
                if t.count > 400 { long += 1 }
            case .code: code += 1
            default: break
            }
        }
        let kinds = [("pictures", pictures), ("stickers", stickers), ("videos", videos), ("files", files), ("links", links),
                     ("long texts", long), ("code", code)].filter { $0.1 > 0 }.map { "\($0.1) \($0.0)" }
        return "\(count) chat rows on screen" + (kinds.isEmpty ? "" : " (" + kinds.joined(separator: ", ") + ")")
    }
}
