import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// The pet: the one chosen in the settings (the TBChat character by default), standing in the window over the content or
/// floating on the desktop. Whichever it is, one director drives it from what goes on in the app:
/// - the sync of the accounts: running while it syncs, failing on an error, a look over the work once it is done, dimmed offline;
/// - something waiting for the user (unread ZenTao notifications): waiting with them;
/// - a new chat message: a wave; a resolved ticket: a jump; the pointer: a look its way (sheets that can look).
/// Where it stands in the window is remembered; so is where it floats (`FloatingPetPanel`). Not in the Flutter app.
struct PetLayer: View {
    let model: ShellModel
    @State private var director = PetDirector()
    @State private var bundled = PetSpriteSheet.bundled()
    private static let xKey = "pet.x", yKey = "pet.y"
    /// The floating pet's size: a little bigger than in the window, where the content is around it.
    static let floatingWidth: CGFloat = 96

    /// How the app is doing, as the pet shows it: trouble first, then something for the user, then work, then no connection.
    static func mood(of statuses: some Collection<AccountSyncStatus>, attention: Bool) -> PetDirector.Mood {
        var busy = false, offline = false
        for s in statuses {
            switch s {
            case .error, .authExpired: return .trouble
            case .syncing: busy = true
            case .offline: offline = true
            case .idle: break
            }
        }
        if attention { return .attention }
        return busy ? .busy : (offline ? .offline : .calm)
    }

    private var settings: AppSettings { model.settings }
    private var sheet: PetSpriteSheet? { model.host.petSheet() ?? bundled }
    private var floats: Bool { settings.showPet && settings.petDisplay == .floating && sheet != nil }

    var body: some View {
        ZStack {
            Color.clear.allowsHitTesting(false)
            if settings.showPet, settings.petDisplay == .inWindow, let sheet {
                PetView(director: director, sheet: sheet, followsCursor: settings.petFollowsCursor) { x, y in
                    UserDefaults.standard.set(x, forKey: Self.xKey); UserDefaults.standard.set(y, forKey: Self.yKey)
                }
                .padding(8)
            }
        }
        .onAppear {
            let d = UserDefaults.standard
            if d.object(forKey: Self.xKey) != nil { director.place(x: d.double(forKey: Self.xKey), y: d.double(forKey: Self.yKey)) }
        }
        .onChange(of: model.celebration.tick) { _, _ in director.celebrate() }
        .onChange(of: model.host.chatTotalUnread()) { old, new in if new > old { director.notify() } }
        .onChange(of: Self.mood(of: model.syncStatuses.values, attention: model.host.petAttention()), initial: true) { old, mood in
            director.mood = mood
            if old == .busy, mood == .calm { director.done() }
        }
        .onChange(of: FloatingKey(floats: floats, sheet: sheet.map { ObjectIdentifier($0.atlas) }, follows: settings.petFollowsCursor),
                  initial: true) { _, key in showFloating(key.floats) }
    }

    private struct FloatingKey: Equatable { var floats: Bool; var sheet: ObjectIdentifier?; var follows: Bool }

    private func showFloating(_ on: Bool) {
        guard on, let sheet else { director.canWander = true; FloatingPetPanel.shared.hide(); return }
        director.canWander = false
        let width = Self.floatingWidth
        let height = width * CGFloat(PetSpriteSheet.cellHeight) / CGFloat(PetSpriteSheet.cellWidth)
        let content = FloatingPetContent(director: director, sheet: sheet, width: width, followsCursor: settings.petFollowsCursor,
                                         onOpen: model.host.revealApp,
                                         onDock: { model.updateSettings { $0.petDisplay = .inWindow } },
                                         onHide: { model.updateSettings { $0.showPet = false } })
        FloatingPetPanel.shared.show(AnyView(content), size: CGSize(width: width, height: height))
    }
}

/// What the floating panel holds: the pet, dragged to move the panel, clicked to bring the app forward, with a menu to put
/// it back in the window or hide it.
struct FloatingPetContent: View {
    let director: PetDirector
    let sheet: PetSpriteSheet
    let width: CGFloat
    let followsCursor: Bool
    let onOpen: () -> Void
    let onDock: () -> Void
    let onHide: () -> Void

    var body: some View {
        PetView(director: director, sheet: sheet, width: width, followsCursor: followsCursor, pausesWithApp: false, movable: false,
                onTap: onOpen)
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { _ in FloatingPetPanel.shared.drag(ended: false) }
                .onEnded { _ in FloatingPetPanel.shared.drag(ended: true) })
            .contextMenu {
                Button(appString("trayOpenApp", "Open WorkNexus"), action: onOpen)
                Button(appString("petShowInWindow", "Put the pet back in the window"), action: onDock)
                Divider()
                Button(appString("petHide", "Hide the pet"), action: onHide)
            }
    }
}
