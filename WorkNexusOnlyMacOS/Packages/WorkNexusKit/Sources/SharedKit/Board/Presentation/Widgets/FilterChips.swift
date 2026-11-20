import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/{filter_option_group,filter_chip}.dart
public struct FilterChipOption: Identifiable {
    public var id: String { label }
    public var label: String
    public var active: Bool
    public var onTap: () -> Void
    public var dotColor: Color?
    public var count: Int?
    /// What the chip does, said when the pointer rests on it.
    public var help: String?
    public init(label: String, active: Bool, onTap: @escaping () -> Void, dotColor: Color? = nil, count: Int? = nil, help: String? = nil) {
        self.label = label; self.active = active; self.onTap = onTap; self.dotColor = dotColor; self.count = count; self.help = help
    }
}

/// A labelled wrap of chips (hidden when there is nothing to choose between).
public struct FilterGroup<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let label: String; let count: Int; let content: Content
    public init(label: String, count: Int, @ViewBuilder content: () -> Content) { self.label = label; self.count = count; self.content = content() }
    public var body: some View {
        if count > 1 {
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                AppSectionHeader(label)
                FlowLayout(spacing: theme.spacing.s6) { content }
            }
            .padding(.bottom, theme.spacing.s14)
        }
    }
}

public struct FilterOptionChip: View {
    @Environment(\.appTheme) private var theme
    let option: FilterChipOption
    public init(_ option: FilterChipOption) { self.option = option }
    public var body: some View {
        let c = theme.colors
        HoverSurface(onTap: option.onTap, selected: option.active, height: theme.sizes.control32 - theme.spacing.s6,
                     fill: option.active ? c.sel : c.panel2, border: theme.showOutline ? c.line : nil, cornerRadius: (theme.sizes.control32 - theme.spacing.s6) / 2) {
            HStack(spacing: theme.spacing.s4) {
                if let dot = option.dotColor { Circle().fill(dot).frame(width: theme.spacing.s6, height: theme.spacing.s6) }
                Text(option.label).font(theme.typography.metaStrong).foregroundStyle(option.active ? c.tx : c.tx2).lineLimit(1)
                if let n = option.count { Text(verbatim: "\(n)").font(theme.typography.meta).foregroundStyle(c.tx3) }
            }
            .padding(.horizontal, theme.spacing.s12)
        }
        .help(option.help ?? "")
    }
}

/// Chips for a few options, a searchable dropdown for many (`dropdownThreshold`).
public struct FilterOptionsGroup: View {
    let label: String; let options: [FilterChipOption]; var dropdownThreshold = 8
    public init(label: String, options: [FilterChipOption], dropdownThreshold: Int = 8) {
        self.label = label; self.options = options; self.dropdownThreshold = dropdownThreshold
    }
    public var body: some View {
        if options.count > 1 {
            if options.count > dropdownThreshold {
                FilterDropdownGroup(label: label, options: options)
            } else {
                FilterGroup(label: label, count: options.count) {
                    ForEach(options) { FilterOptionChip($0) }
                }
            }
        }
    }
}
