import AppKit
import SwiftUI

/// Ported from: lib/core/widgets/app_context_menu.dart
/// One row of an app menu.
public struct AppMenuEntry: Identifiable {
    public let id = UUID()
    /// SF Symbol; left out for a plain-text pick (a view: All, Related to me…).
    public var icon: String?
    public var label: String
    /// Tints the icon (e.g. a status colour); defaults to secondary text.
    public var iconColor: Color?
    /// Shows a trailing check: the current choice in a pick-one menu.
    public var checked: Bool
    /// Drawn in the error colour (delete, retract, remove).
    public var destructive: Bool
    /// A hairline separates this row from the one above.
    public var dividerBefore: Bool

    public init(icon: String? = nil, label: String, iconColor: Color? = nil, checked: Bool = false,
                destructive: Bool = false, dividerBefore: Bool = false) {
        self.icon = icon; self.label = label; self.iconColor = iconColor; self.checked = checked
        self.destructive = destructive; self.dividerBefore = dividerBefore
    }
}

/// The app's menu card: entries as compact rows on a raised panel. `onSelected` gets the picked entry's index.
public struct AppMenuPanel: View {
    @Environment(\.appTheme) private var theme
    let entries: [AppMenuEntry]; let onSelected: (Int) -> Void
    public init(entries: [AppMenuEntry], onSelected: @escaping (Int) -> Void) { self.entries = entries; self.onSelected = onSelected }

    public var body: some View {
        AppPopupCard(padding: theme.spacing.s4) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                    if i > 0, e.dividerBefore {
                        Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline)
                            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
                    }
                    AppMenuRow(entry: e) { onSelected(i) }
                }
            }
            .frame(minWidth: 180)
        }
        .fixedSize()
    }
}

struct AppMenuRow: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let entry: AppMenuEntry; let action: () -> Void
    var body: some View {
        let tint: Color? = entry.destructive ? theme.colors.red : nil
        Button(action: action) {
            HStack(spacing: theme.spacing.s10) {
                if let icon = entry.icon {
                    Image(systemName: icon).font(.system(size: theme.sizes.icon14))
                        .foregroundStyle(tint ?? entry.iconColor ?? theme.colors.tx2).frame(width: theme.sizes.icon16)
                }
                Text(entry.label).font(theme.typography.body).foregroundStyle(tint ?? theme.colors.tx)
                Spacer(minLength: theme.spacing.s12)
                if entry.checked { Image(systemName: "checkmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx2) }
            }
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s8)
            .background(hovering ? (tint ?? theme.colors.tx).opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: theme.radii.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

/// Catches a right-click (or ctrl-click) on the view it backs and reports it in the view's top-left coordinates;
/// every other event passes through to the content beneath.
struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    final class CatcherView: NSView {
        var handler: (CGPoint) -> Void = { _ in }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent else { return nil }
            let secondary = e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
            return secondary ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { handler(convert(event.locationInWindow, from: nil)) }
        override func mouseDown(with event: NSEvent) { handler(convert(event.locationInWindow, from: nil)) }
    }
    func makeNSView(context: Context) -> CatcherView { let v = CatcherView(); v.handler = onRightClick; return v }
    func updateNSView(_ v: CatcherView, context: Context) { v.handler = onRightClick }
}

/// Shows `entries` as a menu with its top-left corner at `anchor` (the modified view's coordinates), flipped to
/// stay inside the view. Dismissed by a click outside or Esc.
public struct AppMenuOverlay: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Binding var anchor: CGPoint?
    let entries: [AppMenuEntry]; let onSelect: (Int) -> Void
    @State private var size: CGSize = .zero

    public func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                if let a = anchor {
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { anchor = nil }
                        AppMenuPanel(entries: entries) { i in anchor = nil; onSelect(i) }
                            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                            .offset(x: place(a.x, size.width, geo.size.width), y: place(a.y, size.height, geo.size.height))
                    }
                    .onExitCommand { anchor = nil }
                }
            }
        }
    }

    /// Opens up / left instead when the menu would run past the far edge.
    private func place(_ at: CGFloat, _ length: CGFloat, _ limit: CGFloat) -> CGFloat {
        let m = theme.spacing.s12
        let p = at + length > limit - m ? at - length : at
        return min(max(p, m), max(limit - length - m, m))
    }
}

public extension View {
    /// A right-click menu: `onSelect` gets the index of the picked entry.
    func appContextMenu(entries: [AppMenuEntry], onSelect: @escaping (Int) -> Void) -> some View {
        modifier(AppContextMenuModifier(entries: entries, onSelect: onSelect))
    }
    /// A menu anchored by the caller (e.g. under a button): set `anchor` to open, nil closes.
    func appMenu(anchor: Binding<CGPoint?>, entries: [AppMenuEntry], onSelect: @escaping (Int) -> Void) -> some View {
        modifier(AppMenuOverlay(anchor: anchor, entries: entries, onSelect: onSelect))
    }
}

struct AppContextMenuModifier: ViewModifier {
    @State private var anchor: CGPoint?
    let entries: [AppMenuEntry]; let onSelect: (Int) -> Void
    func body(content: Content) -> some View {
        content
            .background(RightClickCatcher { anchor = $0 })
            .modifier(AppMenuOverlay(anchor: $anchor, entries: entries, onSelect: onSelect))
    }
}
