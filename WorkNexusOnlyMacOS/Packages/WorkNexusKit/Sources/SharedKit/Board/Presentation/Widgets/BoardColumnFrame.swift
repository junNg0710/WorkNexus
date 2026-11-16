import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/{board_column_frame,board_column_empty_slot}.dart
/// One Kanban column: header (dot, label, count badge, fold button) over a scrolling list of cards. Pass the cards
/// as `content`; `itemCount == 0` shows the empty slot instead (also a drop target highlight).
public struct BoardColumnFrame<Dot: View, Badge: View, Content: View>: View {
    @Environment(\.appTheme) private var theme
    let label: String; let itemCount: Int; let highlighted: Bool; let onFold: (() -> Void)?
    let dot: Dot; let badge: Badge; let content: Content

    public init(label: String, itemCount: Int, highlighted: Bool = false, onFold: (() -> Void)? = nil,
                @ViewBuilder dot: () -> Dot, @ViewBuilder badge: () -> Badge, @ViewBuilder content: () -> Content) {
        self.label = label; self.itemCount = itemCount; self.highlighted = highlighted; self.onFold = onFold
        self.dot = dot(); self.badge = badge(); self.content = content()
    }

    public var body: some View {
        let c = theme.colors
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s8) {
                dot
                Text(label).font(theme.typography.bodyStrong).foregroundStyle(c.tx).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                badge
                if let onFold {
                    AppIconButton("chevron.left.2", help: appString("boardFoldColumn", "Fold column"), action: onFold)
                        .scaleEffect(0.8).frame(width: theme.sizes.icon24, height: theme.sizes.icon24)
                }
            }
            .padding(.horizontal, theme.spacing.s12).padding(.top, theme.spacing.s10).padding(.bottom, theme.spacing.s8)
            .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
            if itemCount == 0 {
                BoardColumnEmptySlot(highlighted: highlighted)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: theme.spacing.s8) { content }
                        .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s8)
                }
            }
        }
        .frame(width: theme.sizes.boardColumn)
        .background(highlighted ? c.sel : c.panel, in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: theme.radii.lg).stroke(c.accent, lineWidth: theme.borders.hairline)
            } else if theme.showOutline {
                RoundedRectangle(cornerRadius: theme.radii.lg).stroke(c.line, lineWidth: theme.borders.hairline)
            }
        }
        .animation(.easeOut(duration: theme.motion.base), value: highlighted)
    }
}

/// Small coloured circle used as a column marker.
public struct BoardColumnDot: View {
    @Environment(\.appTheme) private var theme
    let color: Color
    public init(_ color: Color) { self.color = color }
    public var body: some View { Circle().fill(color).frame(width: theme.spacing.s8, height: theme.spacing.s8) }
}

public struct BoardColumnEmptySlot: View {
    @Environment(\.appTheme) private var theme
    let highlighted: Bool
    public init(highlighted: Bool = false) { self.highlighted = highlighted }
    public var body: some View {
        let c = theme.colors
        VStack(spacing: theme.spacing.s6) {
            Image(systemName: "tray").font(.system(size: theme.sizes.icon20)).foregroundStyle(highlighted ? c.accent : c.tx3)
            Text(appString("noItems", "No items")).font(theme.typography.caption)
                .foregroundStyle(highlighted ? c.tx2 : c.tx3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(theme.spacing.s12)
        .background(highlighted ? c.sel : c.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(highlighted ? c.accent : c.line, lineWidth: theme.borders.hairline))
        .padding(EdgeInsets(top: theme.spacing.s8, leading: theme.spacing.s8, bottom: theme.spacing.s12, trailing: theme.spacing.s8))
    }
}

/// Ported from: lib/shared/board/presentation/widgets/board_folded_column.dart
/// A folded column: a 44pt strip with dot, count and the label rotated; a click opens it.
public struct BoardFoldedColumn<Dot: View, Badge: View>: View {
    @Environment(\.appTheme) private var theme
    let label: String; let highlighted: Bool; let onOpen: () -> Void; let dot: Dot; let badge: Badge

    public init(label: String, highlighted: Bool = false, onOpen: @escaping () -> Void,
                @ViewBuilder dot: () -> Dot, @ViewBuilder badge: () -> Badge) {
        self.label = label; self.highlighted = highlighted; self.onOpen = onOpen; self.dot = dot(); self.badge = badge()
    }

    public var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onOpen, fill: highlighted ? c.sel : c.panel2, border: highlighted ? c.accent : c.line,
                     cornerRadius: theme.radii.lg) {
            VStack(spacing: theme.spacing.s8) {
                dot
                badge
                Text(label).font(theme.typography.bodyStrong).foregroundStyle(c.tx2).lineLimit(1).fixedSize()
                    .rotationEffect(.degrees(-90)).frame(maxHeight: .infinity)
            }
            .padding(.vertical, theme.spacing.s10).frame(width: theme.sizes.boardColumnFolded)
        }
        .help(appFormat("boardOpenColumn", "Open %1$@", label))
    }
}
