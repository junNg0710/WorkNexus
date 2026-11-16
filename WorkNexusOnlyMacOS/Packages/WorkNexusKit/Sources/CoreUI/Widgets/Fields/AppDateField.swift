import SwiftUI

/// Ported from: lib/core/widgets/app_date_field.dart
/// The app's date field: a calendar drops down under it, in the app's colours, with quick picks for the usual
/// dates. The value reads in the app-wide `dateFormat` (`AppSettings.dateFormat`: iso / dmy / long). With
/// `withTime` it holds a date and a time to the minute: the drop-down gains a time row and a "Now" pick, and stays
/// open while a day is picked so the time can follow. Without it a pick closes it.
public struct AppDateField: View {
    @Environment(\.appTheme) private var theme
    @State private var open = false
    let value: Date?; let onChanged: (Date?) -> Void
    let withTime: Bool; let clearable: Bool; let enabled: Bool; let dateFormat: String

    /// - Parameter onChanged: nil only when `clearable` and the user clears the date.
    public init(value: Date?, withTime: Bool = false, clearable: Bool = false, enabled: Bool = true,
                dateFormat: String = "iso", onChanged: @escaping (Date?) -> Void) {
        self.value = value; self.withTime = withTime; self.clearable = clearable; self.enabled = enabled
        self.dateFormat = dateFormat; self.onChanged = onChanged
    }

    private func set(_ v: Date?, close: Bool) { if close { open = false }; onChanged(v) }

    private func combine(day: Date, hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func pickDay(_ day: Date) {
        guard withTime else { return set(day, close: true) }
        let t = Calendar.current.dateComponents([.hour, .minute], from: value ?? Date())
        set(combine(day: day, hour: t.hour ?? 0, minute: t.minute ?? 0), close: false)
    }

    private func pickTime(_ h: Int, _ m: Int) { set(combine(day: value ?? Date(), hour: h, minute: m), close: false) }

    private var quickPicks: [AppDateQuickPick] {
        let cal = Calendar.current, now = Date()
        if withTime {
            let t = cal.dateComponents([.hour, .minute], from: now)
            return [.init(label: appString("datePickNow", "Now"), value: combine(day: cal.startOfDay(for: now), hour: t.hour ?? 0, minute: t.minute ?? 0))]
        }
        let today = cal.startOfDay(for: now)
        return [.init(label: appString("datePickToday", "Today"), value: today),
                .init(label: appString("datePickTomorrow", "Tomorrow"), value: cal.date(byAdding: .day, value: 1, to: today) ?? today),
                .init(label: appString("datePickNextWeek", "In a week"), value: cal.date(byAdding: .day, value: 7, to: today) ?? today)]
    }

    public var body: some View {
        HoverSurface(onTap: { open.toggle() }, enabled: enabled, height: theme.sizes.control32, fill: theme.colors.panel2,
                     border: open ? theme.colors.accent : theme.colors.line) {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: "calendar").font(.system(size: theme.sizes.icon14))
                    .foregroundStyle(enabled && value != nil ? theme.colors.accent : theme.colors.tx3)
                Text(value.map { AppDateFormat.format($0, style: dateFormat, withTime: withTime) } ?? appString("selectNone", "None"))
                    .font(theme.typography.paragraph).foregroundStyle(enabled && value != nil ? theme.colors.tx : theme.colors.tx3).lineLimit(1)
                Spacer(minLength: 0)
                if clearable, enabled, value != nil {
                    AppIconButton("xmark", help: appString("dateClear", "Clear date")) { set(nil, close: true) }
                        .frame(width: theme.sizes.icon24, height: theme.sizes.icon24)
                }
            }
            .padding(.leading, theme.spacing.s12).padding(.trailing, theme.spacing.s8)
        }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            AppDatePickerPanel(picked: value, quickPicks: quickPicks, onPickDay: pickDay,
                               onQuickPick: { set($0, close: true) }) {
                if withTime {
                    let t = Calendar.current.dateComponents([.hour, .minute], from: value ?? Date())
                    HStack(spacing: theme.spacing.s8) {
                        Image(systemName: "clock").foregroundStyle(theme.colors.tx3)
                        Text(appString("dateTime", "Time")).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                        Spacer(minLength: 0)
                        AppTimeInput(hour: t.hour ?? 0, minute: t.minute ?? 0, onChanged: pickTime)
                    }
                }
            }
        }
    }
}

/// Ported from: lib/core/widgets/app_time_input.dart
/// A time of day typed as `HH:mm` (24-hour). Every valid entry is reported at once; leaving the field with an
/// unfinished one puts the last valid time back. ↑ / ↓ step the minutes.
public struct AppTimeInput: View {
    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool
    @State private var text: String
    let hour: Int; let minute: Int; let onChanged: (Int, Int) -> Void

    public init(hour: Int, minute: Int, onChanged: @escaping (_ hour: Int, _ minute: Int) -> Void) {
        self.hour = hour; self.minute = minute; self.onChanged = onChanged
        _text = State(initialValue: AppDateFormat.formatTime(hour: hour, minute: minute))
    }

    public var body: some View {
        TextField(appString("dateTimeHint", "HH:mm"), text: $text)
            .textFieldStyle(.plain).font(theme.typography.paragraph).multilineTextAlignment(.center)
            .frame(width: theme.sizes.control36 * 1.6, height: theme.sizes.control32 - theme.spacing.s4)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.sm))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(focused ? theme.colors.accent : theme.colors.line, lineWidth: theme.borders.hairline))
            .focused($focused)
            .onChange(of: text) { _, new in
                if let t = AppDateFormat.parseTime(new), t.hour != hour || t.minute != minute { onChanged(t.hour, t.minute) }
            }
            .onChange(of: focused) { _, f in if !f { show() } }
            .onChange(of: hour) { _, _ in if AppDateFormat.parseTime(text).map({ $0 != (hour, minute) }) ?? true { show() } }
            .onChange(of: minute) { _, _ in if AppDateFormat.parseTime(text).map({ $0 != (hour, minute) }) ?? true { show() } }
            .onKeyPress(.upArrow) { step(1); return .handled }
            .onKeyPress(.downArrow) { step(-1); return .handled }
    }

    private func show() { text = AppDateFormat.formatTime(hour: hour, minute: minute) }

    private func step(_ delta: Int) {
        let total = ((hour * 60 + minute + delta) % 1440 + 1440) % 1440
        onChanged(total / 60, total % 60)
    }
}
