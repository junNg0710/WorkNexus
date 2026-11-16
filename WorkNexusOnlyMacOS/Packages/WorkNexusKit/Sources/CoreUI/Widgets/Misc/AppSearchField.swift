import SwiftUI

/// Ported from: lib/core/widgets/app_search_field.dart
/// The app's search box: a magnifier, the hint, and a clear button once there is text. Esc clears the text;
/// on an empty box it passes through to the surrounding popover. ↑ / ↓ go to `onMove` (-1 / +1) when set.
public struct AppSearchField: View {
    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool
    @Binding private var text: String
    private let hint: String
    private let onSubmit: (() -> Void)?
    private let onMove: ((Int) -> Void)?
    private let height: CGFloat?
    private let autofocus: Bool

    public init(text: Binding<String>, hint: String, height: CGFloat? = nil, autofocus: Bool = false,
                onSubmit: (() -> Void)? = nil, onMove: ((Int) -> Void)? = nil) {
        _text = text; self.hint = hint; self.height = height; self.autofocus = autofocus
        self.onSubmit = onSubmit; self.onMove = onMove
    }

    public var body: some View {
        HStack(spacing: theme.spacing.s6) {
            Image(systemName: "magnifyingglass").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx3)
            TextField(hint, text: $text)
                .textFieldStyle(.plain).font(theme.typography.body).foregroundStyle(theme.colors.tx)
                .focused($focused).onSubmit { onSubmit?() }
                .onKeyPress(.escape) { text.isEmpty ? .ignored : { text = ""; return .handled }() }
                .onKeyPress(.upArrow) { onMove.map { $0(-1); return .handled } ?? .ignored }
                .onKeyPress(.downArrow) { onMove.map { $0(1); return .handled } ?? .ignored }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx3)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, theme.spacing.s10)
        .frame(height: height ?? theme.sizes.control32)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(focused ? theme.colors.accent : theme.colors.line, lineWidth: theme.borders.hairline))
        .onAppear { if autofocus { focused = true } }
    }
}
