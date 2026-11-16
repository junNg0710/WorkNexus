import SwiftUI

public enum AppButtonStyleKind { case primary, secondary, ghost, danger }

/// Ported from: core/widgets/app_button.dart + app_icon_button.dart.
/// On macOS 26+ the buttons use the system Liquid Glass styles (`.glassProminent` for primary, `.glass` otherwise).
public struct AppButton: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: String
    var systemImage: String?
    var kind: AppButtonStyleKind
    var action: () -> Void

    public init(_ title: String, systemImage: String? = nil, kind: AppButtonStyleKind = .secondary, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.kind = kind; self.action = action
    }

    private var label: some View {
        HStack(spacing: theme.spacing.s6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: theme.sizes.icon14)) }
            Text(title).font(theme.typography.label)
        }
        .padding(.horizontal, theme.spacing.s6)
        .frame(minHeight: theme.sizes.control32 - 8)
    }

    public var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency, kind != .ghost {
            if kind == .primary {
                Button(action: action) { label }.buttonStyle(.glassProminent).tint(theme.colors.accent).controlSize(.large)
            } else {
                Button(action: action) { label }.buttonStyle(.glass)
                    .tint(kind == .danger ? theme.colors.red : nil)
                    .foregroundStyle(kind == .danger ? theme.colors.red : theme.colors.tx).controlSize(.large)
            }
        } else {
            Button(action: action) {
                label.padding(.horizontal, theme.spacing.s6).frame(height: theme.sizes.control32)
                    .foregroundStyle(fg)
                    .background(bg, in: RoundedRectangle(cornerRadius: theme.radii.md))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(border, lineWidth: theme.borders.hairline))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var fg: Color { switch kind { case .primary: theme.colors.accentTx; case .danger: theme.colors.red; default: theme.colors.tx } }
    private var bg: Color { switch kind { case .primary: theme.colors.accent; case .ghost: .clear; default: theme.colors.panel2 } }
    private var border: Color { switch kind { case .primary, .ghost: .clear; case .danger: theme.colors.red.opacity(0.5); default: theme.colors.line } }
}

public struct AppIconButton: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let systemImage: String
    var help: String?
    var action: () -> Void
    public init(_ systemImage: String, help: String? = nil, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.help = help; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: theme.sizes.icon16))
                .foregroundStyle(hovering ? theme.colors.tx : theme.colors.tx2)
                .frame(width: theme.sizes.control32, height: theme.sizes.control32)
                .background(hovering ? theme.colors.tx.opacity(0.08) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.help(help ?? "")
    }
}
