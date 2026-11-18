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
    private var sheet: PetSpriteSheet? { model.host.petSheet() ?? bundled }
    private var floats: Bool { settings.showPet && settings.petDisplay == .floating && sheet != nil }
    private var waiting: Int { model.host.petWaiting() }
    private var mood: PetDirector.Mood { Self.mood(of: model.syncStatuses.values, waiting: waiting) }
    private var status: String {
        PetSignalText.status(mood: mood, statuses: model.syncStatuses.values, unreadChats: model.host.chatTotalUnread(), waiting: waiting)
    }

    var body: some View {
        ZStack {
            Color.clear.allowsHitTesting(false)
            if settings.showPet, settings.petDisplay == .inWindow, let sheet {
                // In a graph of its own: the pet's frames, walks and bubbles never re-render the window (`PetStage`).
                let director = director, inset = Self.inset
                PetStage(petRect: { size in
                    PetView.spriteRect(director: director, room: CGSize(width: size.width - 2 * inset, height: size.height - 2 * inset),
                                       width: PetView.defaultWidth).offsetBy(dx: inset, dy: inset)
                }) {
                    PetView(director: director, sheet: sheet, followsCursor: settings.petFollowsCursor) { x, y in
                        UserDefaults.standard.set(x, forKey: Self.xKey); UserDefaults.standard.set(y, forKey: Self.yKey)
                    }
                    .padding(inset)
                    .environment(\.appTheme, theme)
                }
            }
        }
        .onAppear {
            let d = UserDefaults.standard
            if d.object(forKey: Self.xKey) != nil { director.place(x: d.double(forKey: Self.xKey), y: d.double(forKey: Self.yKey)) }
        }
        .onChange(of: model.celebration.tick) { _, _ in
            director.celebrate(); director.say(PetSignalText.celebrated)
        }
        .onChange(of: model.host.chatTotalUnread()) { old, new in
            guard new > old else { return }
            director.notify(); director.say(PetSignalText.newChats(new - old))
        }
        .onChange(of: mood, initial: true) { old, mood in
            director.mood = mood
            if old == .busy, mood == .calm {
                director.done(); director.say(PetSignalText.synced, for: 4)
            } else if old != mood, let line = PetSignalText.mood(mood, statuses: model.syncStatuses.values, waiting: waiting) {
                director.say(line, for: mood == .busy ? 4 : PetDirector.speechDuration)
            }
        }
        // More notifications waiting while it already waits is news too.
        .onChange(of: waiting) { old, new in
            if new > old, mood == .attention { director.say(PetSignalText.waiting(new)) }
        }
        .onChange(of: status, initial: true) { _, s in director.status = s }
        .onChange(of: FloatingKey(floats: floats, sheet: sheet.map { ObjectIdentifier($0.atlas) }, follows: settings.petFollowsCursor,
                                  dark: theme.colors.isDark), initial: true) { _, key in showFloating(key.floats) }
    }

    private struct FloatingKey: Equatable { var floats: Bool; var sheet: ObjectIdentifier?; var follows: Bool; var dark: Bool }

    private func showFloating(_ on: Bool) {
        guard on, let sheet else { director.canWander = true; FloatingPetPanel.shared.hide(); return }
        director.canWander = false
        let width = Self.floatingWidth
        let height = width * CGFloat(PetSpriteSheet.cellHeight) / CGFloat(PetSpriteSheet.cellWidth)
        let content = FloatingPetContent(director: director, sheet: sheet, width: width, followsCursor: settings.petFollowsCursor,
                                         onOpen: model.host.revealApp,
                                         onDock: { model.updateSettings { $0.petDisplay = .inWindow } },
                                         onHide: { model.updateSettings { $0.showPet = false } })
        FloatingPetPanel.shared.show(AnyView(content.environment(\.appTheme, theme)), petSize: CGSize(width: width, height: height))
    }
}
