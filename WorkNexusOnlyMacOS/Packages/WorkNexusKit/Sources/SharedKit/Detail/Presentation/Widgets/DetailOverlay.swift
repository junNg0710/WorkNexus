import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/detail_overlay.dart
/// The detail slide-over: a scrim over the app (from `railInset` rightwards) and the `DetailPanel` sliding in from the
/// right for the ticket open at the current place (`nav.openTicketId`). Esc or a click on the scrim closes it; ⌘[ (or the mouse's back button) goes
/// back to the previously opened ticket. Width follows the layout setting (two-pane 64% / tabbed 52% of the window,
/// never narrower than 460pt).
public struct DetailOverlayHost: View {
    let controller: DetailController; var railInset: CGFloat?
    public init(controller: DetailController, railInset: CGFloat? = nil) { self.controller = controller; self.railInset = railInset }
    public var body: some View {
        DetailSlideOver(controller: controller, railInset: railInset)
            .appDialog(item: Binding(get: { controller.viewing }, set: { controller.viewing = $0 })) { req in
                AttachmentViewerDialog(controller: controller, request: req) { controller.viewing = nil }
            }
    }
}

struct DetailSlideOver: View {
    @Environment(\.appTheme) private var theme
    let controller: DetailController; var railInset: CGFloat?
    /// The ticket each place's panel shows. Every place keeps its own panel (built, so its scroll and tab stay): going
    /// elsewhere hides it at once and coming back shows it as it was left. The place on screen stays here while it slides closed.
    @State private var shown: [String: String] = [:]
    /// Whether the place on screen's panel is slid in.
    @State private var visible = false
    @FocusState private var focusedPlace: String?

    init(controller: DetailController, railInset: CGFloat?) { self.controller = controller; self.railInset = railInset }

    private func width(_ total: CGFloat, inset: CGFloat) -> CGFloat {
        let two = controller.settings.detailLayout == .twoPane
        let w = min(max(total * (two ? 0.64 : 0.52), two ? 680 : theme.sizes.detailPanel), two ? 1000 : 760)
        return min(w, max(total - inset, 0))
    }

    /// The ticket open at each place (the last of its history).
    private var tops: [String: String] {
        controller.nav.state.ticketHistories.compactMapValues { $0.last }
    }
    private var here: String { controller.nav.state.rail.key }

    /// Called when a history changed (a ticket opened, closed, went back).
    private func sync() {
        let now = tops
        if let id = now[here] {
            if shown[here] != id { controller.model(for: id).tab = .original }
            shown = now
            withAnimation(.easeOut(duration: theme.motion.slow)) { visible = true }
            focusedPlace = here
        } else if visible, let old = shown[here] {
            shown = now.merging([here: old]) { a, _ in a }
            withAnimation(.easeOut(duration: theme.motion.slow)) { visible = false }
            Task {
                try? await Task.sleep(for: .seconds(theme.motion.slow + 0.05))
                if tops[here] == nil { shown = tops }
            }
        } else {
            shown = now
        }
    }

    /// Another place came on screen: its panel (if it has one) is there at once, none slides.
    private func placeChanged() {
        shown = tops
        visible = shown[here] != nil
        if visible { focusedPlace = here }
    }

    var body: some View {
        let inset = railInset ?? theme.sizes.rail
        GeometryReader { geo in
            let w = width(geo.size.width, inset: inset)
            ZStack(alignment: .trailing) {
                if shown[here] != nil {
                    theme.colors.scrim.opacity(visible ? 0.5 : 0).padding(.leading, inset)
                        .contentShape(Rectangle()).onTapGesture { controller.nav.closeTicket() }
                        .allowsHitTesting(visible)
                }
                ForEach(shown.keys.sorted(), id: \.self) { place in
                    if let id = shown[place] {
                        panel(place: place, id: id, width: w)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(shown[here] != nil)
        .onChange(of: controller.nav.state.ticketHistories) { _, h in
            controller.prune(keeping: Set(h.values.flatMap { $0 }))
            sync()
        }
        .onChange(of: controller.nav.state.rail) { _, _ in placeChanged() }
        .task {
            controller.start()
            placeChanged()
        }
    }

    private func panel(place: String, id: String, width w: CGFloat) -> some View {
        let isHere = place == here
        return DetailPanel(controller: controller, ticketId: id) { controller.nav.closeTicket() }
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .shadow(color: theme.colors.scrim.opacity(0.28), radius: 24, x: -4, y: 6)
            .padding(theme.spacing.s8)
            .frame(width: w + theme.spacing.s16).offset(x: isHere && !visible ? w + theme.spacing.s16 : 0)
            .opacity(isHere ? 1 : 0).allowsHitTesting(isHere && visible).disabled(!isHere)
            .focusable().focused($focusedPlace, equals: place).focusEffectDisabled()
            .onKeyPress(.escape) { controller.nav.closeTicket(); return .handled }
            .onBackMouseButton(enabled: isHere && visible) { controller.nav.goBackTicket() }
            .background {
                if isHere { Button("") { controller.nav.goBackTicket() }.keyboardShortcut("[", modifiers: .command).opacity(0) }
            }
    }
}

public extension View {
    /// Shows the ticket detail slide-over over this view.
    func detailOverlay(_ controller: DetailController, railInset: CGFloat? = nil) -> some View {
        overlay { DetailOverlayHost(controller: controller, railInset: railInset) }
    }
}
