import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/core/widgets/app_rail_labeled_button.dart — the 60x54 icon-over-label cell every rail place uses
/// (workspace, chat, accounts, mini apps, settings). Public so the composition root can build the mini-app buttons.
public struct RailLabeledButton<Leading: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    let label: String; let selected: Bool; let badge: Int; let help: String?; let action: () -> Void
    let leading: Leading
    /// The tool this place belongs to: its logo sits on the icon's corner (ZenTao's Chat / Tasks / Bugs / Docs).
    var brand: ProviderType?

    public init(label: String, selected: Bool = false, badge: Int = 0, help: String? = nil, brand: ProviderType? = nil,
                action: @escaping () -> Void, @ViewBuilder leading: () -> Leading) {
        self.label = label; self.selected = selected; self.badge = badge; self.help = help; self.action = action
        self.brand = brand; self.leading = leading()
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: theme.spacing.s2) {
                leading.frame(height: theme.sizes.icon24)
                    .overlay(alignment: .bottomTrailing) {
                        if let brand {
                            BrandLogoBadge(brand, size: 12).padding(1).background(theme.colors.panel, in: Circle())
                                .offset(x: theme.spacing.s8, y: theme.spacing.s4)
                        }
                    }
                // A little smaller rather than cut short: a monospaced face (the Hacker theme, Geist Mono) is wider, and
                // "Dashboard" lost its end.
                Text(label).font(theme.typography.caption).lineLimit(1).minimumScaleFactor(0.8).truncationMode(.tail)
            }
            .padding(.horizontal, theme.spacing.s2)
            .frame(width: 64, height: 54)
            .foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
            .background {
                RoundedRectangle(cornerRadius: theme.radii.lg)
                    .fill(selected ? theme.colors.sel : (hovering ? theme.colors.panel2 : .clear))
                    .animation(reduceMotion ? nil : .easeOut(duration: theme.motion.fast), value: selected)
                    .animation(reduceMotion ? nil : .easeOut(duration: theme.motion.fast), value: hovering)
            }
            .overlay(alignment: .topTrailing) {
                AppCountBadge(badge).offset(x: -theme.spacing.s2, y: theme.spacing.s2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help(help ?? label)
    }
}

public extension RailLabeledButton where Leading == RailSymbol {
    init(_ label: String, systemImage: String, selected: Bool = false, badge: Int = 0, help: String? = nil,
         brand: ProviderType? = nil, action: @escaping () -> Void) {
        self.init(label: label, selected: selected, badge: badge, help: help, brand: brand, action: action) { RailSymbol(systemImage) }
    }
}

/// An SF Symbol sized like the rail's other leading icons.
public struct RailSymbol: View {
    @Environment(\.appTheme) private var theme
    let name: String
    public init(_ name: String) { self.name = name }
    public var body: some View { Image(systemName: name).font(.system(size: theme.sizes.icon20)) }
}

/// A hairline divider inset like the Dart rail's `Divider(indent: md)`.
public struct RailDivider: View {
    @Environment(\.appTheme) private var theme
    public init() {}
    public var body: some View {
        Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline).padding(.horizontal, theme.spacing.s12)
            .padding(.vertical, theme.spacing.s2)
    }
}
