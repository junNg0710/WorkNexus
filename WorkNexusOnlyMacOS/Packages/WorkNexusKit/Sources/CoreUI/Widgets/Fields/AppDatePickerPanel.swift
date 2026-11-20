import SwiftUI

/// Ported from: lib/core/widgets/app_date_picker_panel.dart
/// A one-tap pick above the calendar ("Today", "Now"…).
public struct AppDateQuickPick: Identifiable {
    /// The label: the same pick keeps its identity across redraws.
    public var id: String { label }
    public var label: String
    public var value: Date
    public init(label: String, value: Date) { self.label = label; self.value = value }
}

/// What `AppDateField` drops down: quick picks over a month calendar in the app's colours, then `footer` (the
/// time row when a time is picked too).
public struct AppDatePickerPanel<Footer: View>: View {
    @Environment(\.appTheme) private var theme
    let picked: Date?
    let onPickDay: (Date) -> Void
    let onQuickPick: (Date) -> Void
    let quickPicks: [AppDateQuickPick]
    let footer: Footer

    /// - Parameters: `onPickDay` gets a calendar day at midnight (the caller keeps any time).
    public init(picked: Date?, quickPicks: [AppDateQuickPick] = [], onPickDay: @escaping (Date) -> Void,
                onQuickPick: @escaping (Date) -> Void, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.picked = picked; self.quickPicks = quickPicks; self.onPickDay = onPickDay; self.onQuickPick = onQuickPick
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            if !quickPicks.isEmpty {
                FlowLayout(spacing: theme.spacing.s6) {
                    ForEach(quickPicks) { pick in
                        QuickPickChip(label: pick.label, selected: picked == pick.value) { onQuickPick(pick.value) }
                    }
                }
            }
            DatePicker("", selection: Binding(get: { picked ?? Date() }, set: { onPickDay(Calendar.current.startOfDay(for: $0)) }),
                       displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden().tint(theme.colors.accent)
            footer
        }
        .padding(theme.spacing.s12).frame(width: 280)
        .background(theme.colors.card)
    }
}

private struct QuickPickChip: View {
    @Environment(\.appTheme) private var theme
    let label: String; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(theme.typography.label).foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s4)
                .background(selected ? theme.colors.accent.opacity(0.14) : theme.colors.panel2, in: Capsule())
                .overlay(Capsule().stroke(selected ? theme.colors.accent.opacity(0.5) : theme.colors.line, lineWidth: theme.borders.hairline))
        }.buttonStyle(.plain)
    }
}
