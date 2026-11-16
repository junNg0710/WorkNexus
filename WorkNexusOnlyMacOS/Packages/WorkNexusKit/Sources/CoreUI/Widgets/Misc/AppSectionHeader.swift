import SwiftUI

/// Ported from: lib/core/widgets/app_section_header.dart
/// The small uppercase label that opens a group of rows or fields, with an optional count and a trailing
/// action on the right.
public struct AppSectionHeader<Trailing: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String; let count: Int?; let trailing: Trailing
    public init(_ title: String, count: Int? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title; self.count = count; self.trailing = trailing()
    }
    public var body: some View {
        HStack(spacing: theme.spacing.s6) {
            Text(title.uppercased()).font(theme.typography.caption).tracking(0.6).foregroundStyle(theme.colors.tx3).lineLimit(1)
            if let count { AppCountBadge(count) }
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: theme.sizes.control32 - theme.spacing.s8)
    }
}
