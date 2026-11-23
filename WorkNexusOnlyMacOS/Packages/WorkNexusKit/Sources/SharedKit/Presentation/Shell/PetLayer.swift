import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// The pet: the one chosen in the settings (the TBChat character by default), standing in the window over the content or
/// floating on the desktop. Whichever it is, one director drives it from what goes on in the app, and says what it is
/// reacting to in a speech bubble (`PetSignalText`), so a reaction can be understood, not only seen:
/// - the sync of the accounts: running while it syncs, failing on an error, a look over the work once it is done, dimmed offline;
/// - something waiting for the user (unread ZenTao notifications): waiting with them;
/// - a new chat message: a wave; a resolved ticket: a jump; the pointer: a look its way (sheets that can look).
/// With the pointer on it the bubble sums up the state of things. Where it stands in the window is remembered; so is where
/// it floats (`FloatingPetPanel`). Not in the Flutter app.
struct PetLayer: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    @State private var director = PetDirector()
    @State private var bundled = PetSpriteSheet.bundled()
    private static let xKey = "pet.x", yKey = "pet.y"
    /// The room's margin inside the window.
    static let inset: CGFloat = 8
    /// The floating pet's size: a little bigger than in the window, where the content is around it.
    static let floatingWidth: CGFloat = 96

    /// How the app is doing, as the pet shows it: trouble first, then something for the user, then work, then no connection.
    static func mood(of statuses: some Collection<AccountSyncStatus>, waiting: Int) -> PetDirector.Mood {
        var busy = false, offline = false
        for s in statuses {
            switch s {
            case .error, .authExpired: return .trouble
            case .syncing: busy = true
            case .offline: offline = true
            case .idle: break
            }
        }
        if waiting > 0 { return .attention }
        return busy ? .busy : (offline ? .offline : .calm)
    }

    private var settings: AppSettings { model.settings }
    /// The size the pet is set to, against its usual one.
    private var scale: CGFloat { CGFloat(min(max(settings.petScale, AppSettings.petScaleRange.lowerBound), AppSettings.petScaleRange.upperBound)) }
    /// Whether it says what a message or notification says (the setting), not only that one came.
    private var details: Bool { settings.petShowsDetails }
    /// How long it says a message or notification: a little longer than a short line, to be read.
    static let detailDuration: TimeInterval = 9
    private var sheet: PetSpriteSheet? { model.host.petSheet() ?? bundled }
    private var floats: Bool { settings.showPet && settings.petDisplay == .floating && sheet != nil }
    private var waiting: Int { model.host.petWaiting() }
    private var behavior: PetBehavior { settings.petBehavior }
    /// What it reacts to and says now, as the user set it.
    private var reacts: PetReacts { PetReacts(behavior) }
    /// How the app is doing, as far as the pet shows it: without what the user told it not to react to.
    private var mood: PetDirector.Mood {
        let reacts = reacts
        return Self.mood(of: reacts.to(.sync) ? Array(model.syncStatuses.values) : [], waiting: reacts.to(.notifications) ? waiting : 0)
    }
    /// What the pointer resting on it is told: how things really are, whatever it reacts to.
    private var status: String {
        let mood = Self.mood(of: model.syncStatuses.values, waiting: waiting)
        return PetSignalText.status(mood: mood, statuses: model.syncStatuses.values, unreadChats: model.host.chatTotalUnread(), waiting: waiting)
    }

    var body: some View {
        ZStack {
            Color.clear.allowsHitTesting(false)
            if settings.showPet, settings.petDisplay == .inWindow, let sheet {
                // In a graph of its own: the pet's frames, walks and bubbles never re-render the window (`PetStage`).
                let director = director, inset = Self.inset, width = PetView.defaultWidth * scale
                PetStage(petRect: { size in
                    PetView.pointerRect(director: director, room: CGSize(width: size.width - 2 * inset, height: size.height - 2 * inset),
                                        width: width).offsetBy(dx: inset, dy: inset)
                }) {
                    PetView(director: director, sheet: sheet, width: width, followsCursor: settings.petFollowsCursor, onOpenLink: model.host.petOpen) { x, y in
                        UserDefaults.standard.set(x, forKey: Self.xKey); UserDefaults.standard.set(y, forKey: Self.yKey)
                    }
                    .padding(inset)
                    // Right-click: the panic switch's demo trigger, while demo mode is on (no menu otherwise). The stage
                    // only takes the pointer over the pet, so this never shadows the content's own menus.
                    .contextMenu {
                        if let runDemo = model.host.petDemo() { Button(appString("panicSwitchMenuDemo", "Demo"), action: runDemo); Divider() }
                        PetQuickMenu(model: model)
                    }
                    .environment(\.appTheme, theme)
                    .environment(\.petTripleTap, model.host.petTripleTap)
                }
            }
        }
        .onAppear { if !floats { placeInWindow() } }   // floating, its place is along the panel's strip
        .onChange(of: model.celebration.tick) { _, _ in
            guard reacts.to(.celebration) else { return }
            director.celebrate(); say(PetSignalText.celebrated)
        }
        .onChange(of: model.host.chatTotalUnread()) { old, new in
            // With the details on, the message itself is news (`petChatNews`), said when it comes.
            guard new > old, !details, reacts.to(.chat) else { return }
            director.notify(); say(PetSignalText.newChats(new - old))
        }
        // An app on the rail has news (its Dock badge went up, a web mini app notified): a click on the line opens it.
        .onChange(of: model.petAppNews) { _, news in
            guard let news, reacts.to(.apps) else { return }
            director.notify(); say(PetSignalText.app(news, details: details), for: Self.detailDuration, link: news.link)
        }
        .onChange(of: model.petChatNews) { _, news in
            guard details, let news, reacts.to(.chat) else { return }
            director.notify(); say(PetSignalText.chat(news), for: Self.detailDuration, link: news.link)
        }
        .onChange(of: mood, initial: true) { old, mood in
            director.mood = mood
            if old == .busy, mood == .calm {
                director.done(); say(PetSignalText.synced, for: 4)
            } else if old != mood, let line = PetSignalText.mood(mood, statuses: model.syncStatuses.values, waiting: waiting) {
                say(line, for: mood == .busy ? 4 : PetDirector.speechDuration)
            }
        }
        // More notifications waiting while it already waits is news too.
        .onChange(of: waiting) { old, new in
            guard new > old, mood == .attention else { return }
            if details, let notice = model.host.petNewestWaiting() { say(notice.text, for: Self.detailDuration, link: notice.link) }
            else { say(PetSignalText.waiting(new)) }
        }
        .onChange(of: status, initial: true) { _, s in director.status = s }
        .onChange(of: settings.petStaysWhenAppHides, initial: true) { _, on in FloatingPetPanel.shared.staysWhenAppHides = on }
        .onChange(of: behavior, initial: true) { _, behavior in apply(behavior) }
        // "Quiet for 1 hour" is over: it reacts and speaks again.
        .task(id: behavior.quietUntil) {
            guard let until = behavior.quietUntil else { return }
            try? await Task.sleep(for: .seconds(max(until.timeIntervalSinceNow, 0)))
            if !Task.isCancelled { model.updateSettings { $0.petBehavior.quietUntil = nil } }
        }
        .onChange(of: FloatingKey(floats: floats, sheet: sheet.map { ObjectIdentifier($0.atlas) }, follows: settings.petFollowsCursor,
                                  dark: theme.colors.isDark, scale: scale, roam: behavior.roam), initial: true) { _, key in showFloating(key.floats) }
    }

    private struct FloatingKey: Equatable {
        var floats: Bool; var sheet: ObjectIdentifier?; var follows: Bool; var dark: Bool; var scale: CGFloat; var roam: PetRoam
    }

    /// Says a line in its bubble, unless it is told not to speak, for as long as the user likes lines to stay.
    private func say(_ text: String, for seconds: TimeInterval? = nil, link: String? = nil) {
        let reacts = reacts
        guard reacts.speaks else { return }
        director.say(text, for: reacts.seconds(seconds ?? PetDirector.speechDuration), link: link)
    }

    /// How the user wants it to move and speak, handed to its director.
    private func apply(_ behavior: PetBehavior) {
        director.canWander = behavior.activity.wanders
        director.pause = behavior.activity.pause
        director.idleGestures = behavior.idleGestures
        director.statusOnHover = behavior.statusOnHover
        // Told to stand still in the middle of a walk: it stops where it is.
        if !behavior.activity.wanders, director.walk != nil { director.place(x: director.x(at: Date()), y: director.y) }
        if !PetReacts(behavior).speaks { director.hush() }
    }

    private func showFloating(_ on: Bool) {
        guard on, let sheet else {
            // Back in the window: it stands where it stood there.
            if FloatingPetPanel.shared.isShown { FloatingPetPanel.shared.hide(); placeInWindow() }
            return
        }
        let width = Self.floatingWidth * scale
        let height = width * CGFloat(PetSpriteSheet.cellHeight) / CGFloat(PetSpriteSheet.cellWidth)
        let content = FloatingPetContent(director: director, sheet: sheet, width: width, followsCursor: settings.petFollowsCursor,
                                         onOpen: model.host.revealApp, onToggle: model.host.toggleApp, onOpenLink: model.host.petOpen,
                                         onDock: { model.updateSettings { $0.petDisplay = .inWindow } },
                                         onHide: { model.updateSettings { $0.showPet = false } }, demo: model.host.petDemo,
                                         quick: PetQuickMenu(model: model))
        let theme = theme
        FloatingPetPanel.shared.show(AnyView(content.environment(\.appTheme, theme).environment(\.petTripleTap, model.host.petTripleTap)), petSize: CGSize(width: width, height: height)) { text, tail in
            AnyView(FloatingPetBubble(text: text, tailShift: tail).environment(\.appTheme, theme))
        }
        // On the desktop it strolls along a strip around where it was put, or the whole screen.
        FloatingPetPanel.shared.roamsScreen = behavior.roam == .screen
        let stroll = FloatingPetPanel.shared.stroll
        director.roomWidth = stroll.points; director.place(x: stroll.x, y: director.y)
    }

    /// Where it was left in the window, if anywhere.
    private func placeInWindow() {
        let d = UserDefaults.standard
        if d.object(forKey: Self.xKey) != nil { director.place(x: d.double(forKey: Self.xKey), y: d.double(forKey: Self.yKey)) }
    }
}
