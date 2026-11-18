import CoreUI
import SwiftUI

/// What the floating panel holds: the pet, with its speech bubble above it while it says something (or while the pointer
/// rests on it, the state of things). Dragged it moves the panel, clicked it brings the app forward, and its menu puts it
/// back in the window or hides it. The panel grows for the bubble and shrinks back after (`FloatingPetPanel.setBubble`).
/// Not in the Flutter app.
struct FloatingPetContent: View {
    @Environment(\.appTheme) private var theme
    let director: PetDirector
    let sheet: PetSpriteSheet
    let width: CGFloat
    let followsCursor: Bool
    let onOpen: () -> Void
    let onDock: () -> Void
    let onHide: () -> Void
    @State private var hovering = false

    private var height: CGFloat { width * CGFloat(PetSpriteSheet.cellHeight) / CGFloat(PetSpriteSheet.cellWidth) }

    var body: some View {
        let text = director.bubble(hovering: hovering)
        // Near a screen edge the panel is kept on the screen and the pet stands off its middle: the tail follows the pet.
        let shift = FloatingPetPanel.shared.petShift
        VStack(spacing: 0) {
            if let text {
                VStack(spacing: -theme.borders.hairline) {
                    PetSpeechBubble(text, showsTail: false)
                    PetBubbleTail().offset(x: shift)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            }
            PetView(director: director, sheet: sheet, width: width, followsCursor: followsCursor, pausesWithApp: false, movable: false,
                    showsBubble: false, onTap: onOpen)
                .frame(width: width, height: height)
                .onHover { hovering = $0 }
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { _ in FloatingPetPanel.shared.drag(ended: false) }
                    .onEnded { _ in FloatingPetPanel.shared.drag(ended: true) })
                .contextMenu {
                    Button(appString("trayOpenApp", "Open WorkNexus"), action: onOpen)
                    Button(appString("petShowInWindow", "Put the pet back in the window"), action: onDock)
                    Divider()
                    Button(appString("petHide", "Hide the pet"), action: onHide)
                }
                .offset(x: shift)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: text != nil, initial: true) { _, shown in FloatingPetPanel.shared.setBubble(shown) }
    }
}
