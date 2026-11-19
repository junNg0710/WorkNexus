import CoreUI
import SwiftUI

/// What the floating panel holds: the pet. Dragged it moves the panel (and makes that its new place to stroll around),
/// clicked it opens what it is saying (a message, a notification) or else brings the app forward, and its menu puts it
/// back in the window or hides it (and, in the panic switch's demo mode, offers "Demo"). When it walks the panel goes
/// with it (`FloatingPetPanel.follow`). What it says (or, while the pointer rests on it, the state of things) goes to
/// the bubble's own panel above it (`FloatingPetPanel.setBubble`), so the pet's panel never changes size. Not in the
/// Flutter app.
struct FloatingPetContent: View {
    let director: PetDirector
    let sheet: PetSpriteSheet
    let width: CGFloat
    let followsCursor: Bool
    let onOpen: () -> Void
    let onOpenLink: (String) -> Void
    let onDock: () -> Void
    let onHide: () -> Void
    /// The panic switch's demo trigger while demo mode is on (`ShellHost.petDemo`): "Demo" heads the menu.
    var demo: () -> (() -> Void)? = { nil }
    @State private var hovering = false

    private var height: CGFloat { width * CGFloat(PetSpriteSheet.cellHeight) / CGFloat(PetSpriteSheet.cellWidth) }

    var body: some View {
        PetView(director: director, sheet: sheet, width: width, followsCursor: followsCursor, pausesWithApp: false, movable: false,
                showsBubble: false, onTap: onOpen, onOpenLink: onOpenLink)
            .frame(width: width, height: height)
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { _ in
                    if director.walk != nil { director.place(x: director.x(at: Date()), y: director.y) }   // stops the walk
                    FloatingPetPanel.shared.drag(ended: false)
                }
                .onEnded { _ in FloatingPetPanel.shared.drag(ended: true); syncStroll() })
            .contextMenu {
                if let runDemo = demo() {
                    Button(appString("panicSwitchMenuDemo", "Demo"), action: runDemo)
                    Divider()
                }
                Button(appString("trayOpenApp", "Open WorkNexus"), action: onOpen)
                Button(appString("petShowInWindow", "Put the pet back in the window"), action: onDock)
                Divider()
                Button(appString("petHide", "Hide the pet"), action: onHide)
            }
            .onChange(of: director.walk) { _, walk in
                FloatingPetPanel.shared.follow(walk)
                // Done walking: where it now stands along the strip (the app's window may have moved or changed size).
                if walk == nil { syncStroll() }
            }
            .onChange(of: Bubble(text: director.bubble(hovering: hovering), link: director.link), initial: true) { _, bubble in
                let director = director, open = onOpenLink
                FloatingPetPanel.shared.setBubble(bubble.text, onTap: bubble.link.map { link in { director.hush(); open(link) } })
            }
    }

    private struct Bubble: Equatable { var text: String?; var link: String? }

    private func syncStroll() {
        let stroll = FloatingPetPanel.shared.stroll
        director.roomWidth = stroll.points; director.place(x: stroll.x, y: director.y)
    }
}

/// The floating pet's speech bubble, at the bottom of its panel, with the tail `tailShift` points off the middle so it
/// points at the pet when the panel was kept on the screen.
struct FloatingPetBubble: View {
    @Environment(\.appTheme) private var theme
    let text: String
    let tailShift: CGFloat

    var body: some View {
        VStack(spacing: -theme.borders.hairline) {
            PetSpeechBubble(text, showsTail: false)
            PetBubbleTail().offset(x: tailShift)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
