/// Not in the Flutter app.
import CoreDomain
import Foundation

/// What the Chat page's search can be narrowed by in the title bar, with the names shown: the kind of thing (its tabs) and
/// how far back it looks (a menu). Ids are what the search is told was picked.
public enum ChatSearchChoices {
    public static let allKinds = "all"

    /// The tabs: everything, then one kind each.
    public static var kinds: [(id: String, title: String)] {
        [(allKinds, shellString("chatSearchKindAll", "All")), (ChatSearchKind.messages.rawValue, shellString("chatGlobalSearchMessages", "Messages")),
         (ChatSearchKind.files.rawValue, shellString("chatSearchKindFiles", "Files")), (ChatSearchKind.links.rawValue, shellString("chatSearchKindLinks", "Links")),
         (ChatSearchKind.images.rawValue, shellString("chatSearchKindImages", "Images"))]
    }

    public static func kind(_ id: String?) -> ChatSearchKind? { id.flatMap(ChatSearchKind.init(rawValue:)) }

    /// How far back: any time first.
    public static var periods: [(id: String, title: String)] {
        ChatSearchPeriod.allCases.map { (id($0), ChatShellLabels.searchPeriodLabel($0)) }
    }

    public static func since(_ id: String?, now: Date = Date()) -> Date? {
        ChatSearchPeriod.allCases.first { self.id($0) == id }?.since(now)
    }

    private static func id(_ p: ChatSearchPeriod) -> String {
        switch p { case .all: "all"; case .week: "week"; case .month: "month"; case .quarter: "quarter"; case .year: "year" }
    }

    /// The words of a search without its filters, as the search inside one chat takes them (a phrase back in quotes).
    public static func words(_ terms: [String]) -> String {
        terms.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}
