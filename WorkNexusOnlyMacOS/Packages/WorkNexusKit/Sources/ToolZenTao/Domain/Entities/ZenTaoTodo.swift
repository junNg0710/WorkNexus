/// Not in the Flutter app.
import Foundation

/// A personal todo about to be made in ZenTao ("My > Todo"): what to do, by when, how urgent, and a note.
public struct ZenTaoTodoDraft: Equatable, Sendable {
    public var name: String
    /// The note, as plain text (sent to ZenTao as HTML, see `descHtml`).
    public var desc: String
    public var date: Date
    /// ZenTao's todo priority, 1 (highest) … 4.
    public var pri: Int

    public static let priorities = 1...4
    public static let defaultPriority = 3
    public static let nameLimit = 255

    public init(name: String, desc: String = "", date: Date, pri: Int = ZenTaoTodoDraft.defaultPriority) {
        self.name = name; self.desc = desc; self.date = date; self.pri = pri
    }

    /// The note as the HTML ZenTao stores: escaped, a paragraph per blank-line block, line breaks kept.
    public var descHtml: String {
        let escaped = desc.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return escaped.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br/>"))</p>" }.joined()
    }
}
