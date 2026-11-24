/// Not in the Flutter app.
import CoreUI
import SwiftUI

/// What the title bar's search looks through on a place that has its own (the Chat page: chats, people and messages)
/// instead of the workspace's tickets. The app provides it (`ShellHost.placeSearch`); the shell knows nothing of chat.
public struct PlaceSearch {
    public var placeholder: String
    /// The kinds of thing it can be narrowed to, as tabs over the results; the first is "all" and is where it starts.
    public var scopes: [PlaceSearchScope]
    /// Other things to narrow it by, each a small menu beside the tabs (a time range).
    public var options: [PlaceSearchOption]
    /// A line under the results (what is - and is not - searched).
    public var note: String?
    /// What a search finds. With nothing typed it is asked only once a scope other than the first is picked.
    public var search: @MainActor (PlaceSearchRequest) async -> [PlaceSearchHit]
    /// What is offered while the field is clicked and still empty (the last searches, the places last used).
    public var suggestions: @MainActor () async -> [PlaceSearchHit]
    /// Told the query one of its results was opened from, to offer it again.
    public var remember: @MainActor (String) -> Void

    public init(placeholder: String, scopes: [PlaceSearchScope] = [], options: [PlaceSearchOption] = [], note: String? = nil,
                suggestions: @escaping @MainActor () async -> [PlaceSearchHit] = { [] }, remember: @escaping @MainActor (String) -> Void = { _ in },
                search: @escaping @MainActor (PlaceSearchRequest) async -> [PlaceSearchHit]) {
        self.placeholder = placeholder; self.scopes = scopes; self.options = options; self.note = note
        self.suggestions = suggestions; self.remember = remember; self.search = search
    }
}

public struct PlaceSearchScope: Identifiable, Hashable {
    public var id: String
    public var title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

/// One thing a search can be narrowed by, picked from a menu; its first choice is where it starts.
public struct PlaceSearchOption: Identifiable {
    public var id: String
    public var icon: String
    public var help: String
    public var choices: [PlaceSearchScope]
    public init(id: String, icon: String, help: String, choices: [PlaceSearchScope]) { self.id = id; self.icon = icon; self.help = help; self.choices = choices }
}

public struct PlaceSearchRequest {
    public var query: String
    /// Every match (the "Show all" row was picked) instead of the first few.
    public var all: Bool
    /// The id of the tab picked; nil when the search has none.
    public var scope: String?
    /// The choice picked for each option, by the option's id.
    public var options: [String: String]
}

public struct PlaceSearchHit: Identifiable {
    /// What picking it does.
    public enum Action {
        /// Goes there; the search closes.
        case open(() -> Void)
        /// Puts this text in the field and searches it (a search made before, a filter completed).
        case fill(String)
        /// Lists every match instead of the first few.
        case showAll
    }

    /// A small button at the end of the row for something else to do with the hit (search on inside its chat).
    public struct Extra {
        public var icon: String
        public var help: String
        public var run: () -> Void
        public init(icon: String, help: String, run: @escaping () -> Void) { self.icon = icon; self.help = help; self.run = run }
    }

    public var id: String
    /// The group it is listed under ("Chats", "Messages").
    public var section: String
    public var icon: String
    public var title: String
    /// Written before the subtitle, never marked (who said it).
    public var lead: String
    public var subtitle: String
    public var detail: String
    /// The words searched, shown marked where they are found: in the subtitle, and in the title when it is what matched.
    public var marks: [String]
    public var marksTitle: Bool
    /// Drawn in place of the icon (a chat's picture).
    public var leading: AnyView?
    public var extra: Extra?
    public var action: Action

    public init(id: String, section: String, icon: String, title: String, lead: String = "", subtitle: String = "", detail: String = "",
                marks: [String] = [], marksTitle: Bool = false, leading: AnyView? = nil, extra: Extra? = nil, action: Action) {
        self.id = id; self.section = section; self.icon = icon; self.title = title; self.lead = lead; self.subtitle = subtitle
        self.detail = detail; self.marks = marks; self.marksTitle = marksTitle; self.leading = leading; self.extra = extra; self.action = action
    }

    public init(id: String, section: String, icon: String, title: String, subtitle: String, detail: String = "", open: @escaping () -> Void) {
        self.init(id: id, section: section, icon: icon, title: title, subtitle: subtitle, detail: detail, action: .open(open))
    }

    var showsAll: Bool { if case .showAll = action { true } else { false } }
}
