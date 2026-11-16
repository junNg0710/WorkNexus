import SwiftUI

/// Ported from: lib/core/widgets/inline_status.dart
/// The small centred spinner a settings card shows while its slot is still loading.
public struct AppInlineSpinner: View {
    @Environment(\.appTheme) private var theme
    public init() {}
    public var body: some View {
        ProgressView().controlSize(.small)
            .frame(maxWidth: .infinity).padding(.vertical, theme.spacing.s12)
    }
}

/// A short line of explanatory — or, with `isError`, failing — text inside a card or filter group.
public struct AppInlineNote: View {
    @Environment(\.appTheme) private var theme
    let text: String; let isError: Bool
    public init(_ text: String, isError: Bool = false) { self.text = text; self.isError = isError }
    public var body: some View {
        Text(text).font(theme.typography.paragraph).foregroundStyle(isError ? theme.colors.red : theme.colors.tx3)
    }
}
