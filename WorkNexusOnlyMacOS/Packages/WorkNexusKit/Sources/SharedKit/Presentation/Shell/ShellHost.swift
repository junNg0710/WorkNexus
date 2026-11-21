import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Slots the composition root (`App/`) fills with views of features / tools the shell must not import (rule 10.1):
/// chat, mini apps, the workspace overview pages, the ticket editor, notifications, update, settings. Every slot has an
/// inert default, so a bare `ShellModel` still renders (tests, previews). Closures run inside view bodies, so reading an
/// `@Observable` model in one makes that view reactive.
public struct ShellHost {
    /// Unread chat messages of a ZenTao account (rail badge) and across all of them (Chat button).
    public var chatUnread: (_ accountId: String) -> Int = { _ in 0 }
    public var chatTotalUnread: () -> Int = { 0 }
    /// The chat of a ZenTao account (the Chat rail place).
    public var chatView: (Account) -> AnyView = { _ in AnyView(EmptyView()) }
    /// The page of a workspace section (`overview` / `integrations` / `members` / `settings`).
    public var workspacePage: (_ section: String) -> AnyView = { _ in AnyView(EmptyView()) }
    /// The page of a settings section (`general` / `appearance` / `pet` / `chat` / `translation` / `panicSwitch` / `cache`).
    public var settingsPage: (_ section: String) -> AnyView = { _ in AnyView(EmptyView()) }
    /// Rail: one button per mini app plus "Add".
    public var miniAppRail: () -> AnyView = { AnyView(EmptyView()) }
    /// The mounted mini-app web views (kept alive while hidden); shown while a mini app is selected.
    public var miniAppStack: () -> AnyView = { AnyView(EmptyView()) }
    /// The full-screen ticket editor of `AppNavState.editor`.
    public var editor: (TicketEditorRoute) -> AnyView = { _ in AnyView(EmptyView()) }
    /// Rail: the notifications bell and the update button (each hides itself when it has nothing to say).
    public var bell: () -> AnyView = { AnyView(EmptyView()) }
    public var updateButton: () -> AnyView = { AnyView(EmptyView()) }
    /// A strip under the title bar (the update banner).
    public var banner: () -> AnyView = { AnyView(EmptyView()) }
    /// Over the content, under the detail slide-over (the notifications panel); `railInset` is where the rail ends.
    public var overlay: (_ railInset: CGFloat) -> AnyView = { _ in AnyView(EmptyView()) }
    /// Closes the topmost host overlay (the notifications panel) and says whether there was one: Esc asks it after the ticket panel.
    public var dismissOverlay: () -> Bool = { false }
    /// The quick-settings popover of the title bar's gear.
    public var quickSettings: () -> AnyView = { AnyView(EmptyView()) }
    /// The name of a mini app (the breadcrumb shows it, never the id); nil while it is unknown.
    public var miniAppName: (_ id: String) -> String? = { _ in nil }
    /// The new bug / task choices of the rail's "+" menu (a bug and a task per ZenTao account, filed into the open product /
    /// execution); nil, or an empty list, hides the button. Closures run in a view body, so reading the nav state in one makes
    /// the menu follow it.
    public var newTicketTargets: (() -> [NewTicketTarget])?
    /// What the title bar's search looks through on `rail` when that place has a search of its own (the Chat page);
    /// nil: the workspace's tickets.
    public var placeSearch: (RailTarget) -> PlaceSearch? = { _ in nil }
    /// The sprite sheet of the pet chosen in the settings; nil: the TBChat character that ships with the app.
    public var petSheet: () -> PetSpriteSheet? = { nil }
    /// How many things wait for the user (unread ZenTao notifications): the pet waits with them and says how many.
    public var petWaiting: () -> Int = { 0 }
    /// The newest unread ZenTao notification, for the pet to say it (`petShowsDetails`); nil: none.
    public var petNewestWaiting: () -> PetNotice? = { nil }
    /// Opens what a line of the pet's links to (a chat, a notification's ticket), bringing the app forward.
    public var petOpen: (String) -> Void = { _ in }
    /// Brings the app's window forward ("Open WorkNexus" in the floating pet's menu).
    public var revealApp: () -> Void = {}
    /// A click on the floating pet: brings the app forward from another app, and hides it again when it is already in front
    /// (the pet is then a switch between the app and whatever the user was in).
    public var toggleApp: () -> Void = {}
    /// The pet's alert gesture (held, or two or three quick clicks, in the window or floating): the panic switch's official
    /// trigger; nil: clicks act as usual.
    public var petTripleTap: PetTripleTap?
    /// "Demo" in the pet's right-click menu (in the window and floating): the panic switch's demo trigger, while demo mode is
    /// on; nil: no such item. Runs in a view body, so reading an `@Observable` model in it keeps the menu in step.
    public var petDemo: () -> (() -> Void)? = { nil }
    /// Whether a settings section is listed (the panic switch's page only for the ZenTao it is offered for); runs in a view
    /// body, like `petDemo`.
    public var settingsSectionVisible: (_ section: String) -> Bool = { _ in true }
    public init() {}
}

/// One entry of the rail's "+" menu: a new bug or task of a ZenTao account, as the editor route that opens it.
public struct NewTicketTarget: Identifiable, Equatable, Sendable {
    public var id: String { "\(accountId)|\(isBug ? "bug" : "task")" }
    public let accountId: String
    public let accountHandle: String
    public let isBug: Bool
    public let route: TicketEditorRoute
    public init(accountId: String, accountHandle: String, isBug: Bool, route: TicketEditorRoute) {
        self.accountId = accountId; self.accountHandle = accountHandle; self.isBug = isBug; self.route = route
    }
}
