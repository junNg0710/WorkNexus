import SwiftUI

/// Ported from: lib/core/widgets/resize_handle.dart
/// A thin grab strip that resizes whatever sits on its left: a resize cursor on hover, an accent line along
/// its right edge while hovered or dragging, horizontal drag deltas forwarded to `onDelta`.
public struct ResizeHandle: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    @State private var dragging = false
    @State private var last: CGFloat = 0
    public static let width: CGFloat = 8
    private let onDelta: (CGFloat) -> Void
    private let onEnd: () -> Void
    private let onReset: (() -> Void)?

    /// - Parameters: `onEnd` is the moment to persist the new size; `onReset` (double-click) restores the default.
    public init(onDelta: @escaping (CGFloat) -> Void, onEnd: @escaping () -> Void = {}, onReset: (() -> Void)? = nil) {
        self.onDelta = onDelta; self.onEnd = onEnd; self.onReset = onReset
    }

    public var body: some View {
        Color.clear
            .frame(width: Self.width).frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Rectangle().fill(hovering || dragging ? theme.colors.accent : .clear).frame(width: theme.borders.thick)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .pointerStyle(.columnResize)
            .onTapGesture(count: 2) { onReset?() }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if !dragging { dragging = true; last = 0 }
                    onDelta(v.translation.width - last); last = v.translation.width
                }
                .onEnded { _ in dragging = false; onEnd() })
    }
}
