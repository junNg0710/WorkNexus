import CoreUI
import SwiftUI

/// Small building blocks of the settings pages (lib/core/widgets/{settings_section_heading,quick_settings_parts}.dart):
/// a scrolling page, titled cards, label + control rows, and typed pickers over `AppSettings` fields.
struct SettingsPage<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.s16) {
                Text(title).font(theme.typography.title).foregroundStyle(theme.colors.tx)
                content
            }
            .frame(maxWidth: 720, alignment: .leading).padding(theme.spacing.s24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(theme.colors.bg)
    }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                if let subtitle { Text(subtitle).font(theme.typography.meta).foregroundStyle(theme.colors.tx3) }
            }
            content
        }
        .padding(theme.cardPadding + theme.spacing.s2).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

/// A label (+ hint) on the left, its control on the right.
struct SettingsRow<Control: View>: View {
    @Environment(\.appTheme) private var theme
    let label: String
    var hint: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing.s12) {
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(label).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
                if let hint { Text(hint).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: theme.spacing.s12)
            control
        }
    }
}

/// A segmented choice over any hashable values (variant, surface, density…).
struct SettingsSegmented<T: Hashable>: View {
    let values: [(T, String)]
    let value: T
    let onChange: (T) -> Void

    var body: some View {
        AppSegmentedTabs(values.map { v in AppSegmentedTab(label: v.1, active: v.0 == value) { onChange(v.0) } })
    }
}

struct SettingsToggleRow: View {
    let label: String
    var hint: String?
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        SettingsRow(label: label, hint: hint) {
            Toggle("", isOn: Binding(get: { isOn }, set: onChange)).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct SettingsTextField: View {
    @Environment(\.appTheme) private var theme
    let label: String
    @Binding var text: String
    var prompt = ""
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            Text(label).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
            Group {
                if secure { SecureField(prompt, text: $text) } else { TextField(prompt, text: $text) }
            }
            .textFieldStyle(.plain).font(theme.typography.body).padding(.horizontal, theme.spacing.s10)
            .frame(height: theme.sizes.control36)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }
}

/// A slider with its value written beside it.
struct SettingsSlider: View {
    @Environment(\.appTheme) private var theme
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.05
    var format: (Double) -> String = { String(format: "%.2f", $0) }
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            Slider(value: Binding(get: { value }, set: onChange), in: range, step: step).frame(width: 180).tint(theme.colors.accent)
            Text(format(value)).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).frame(width: 44, alignment: .trailing)
        }
    }
}
