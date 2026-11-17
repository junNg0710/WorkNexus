/// Ported from: lib/core/util/hours_text.dart, lib/shared/detail/presentation/widgets/action_dialog_scaffold.dart (`FieldLabel`)
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Hours as ZenTao shows them: at most two decimals, no trailing zeros (`2.5`, `16`).
public func zentaoHoursText(_ hours: Double) -> String {
    ZentaoNumberFormat.hours.string(from: NSNumber(value: hours)) ?? "\(hours)"
}

/// Number formatters made once (making one costs far more than using it; detail rows redraw often).
enum ZentaoNumberFormat {
    nonisolated(unsafe) static let hours: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.minimumFractionDigits = 0; f.maximumFractionDigits = 2
        f.numberStyle = .decimal; f.usesGroupingSeparator = false
        return f
    }()
    nonisolated(unsafe) static let percent: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .percent; f.maximumFractionDigits = 0
        return f
    }()
}

/// Hours typed in a field: 0 when empty, NaN (refused) when not a number. A comma counts as the decimal point.
public func zentaoParseHours(_ text: String) -> Double {
    let value = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    return value.isEmpty ? 0 : (Double(value) ?? .nan)
}

/// A field's label in an action dialog, with the gap above its input.
struct ZentaoFieldLabel: View {
    @Environment(\.appTheme) private var theme
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { SectionLabel(text).padding(.bottom, theme.spacing.s6) }
}

/// Keeps `dateFormat` in step with the app settings (the detail sections show dates in the user's format).
private struct ZentaoDateFormatWatch: ViewModifier {
    let deps: ZentaoDependencies
    @Binding var dateFormat: String
    func body(content: Content) -> some View {
        content.task { for await s in deps.services.settings.watch() { dateFormat = s.dateFormat } }
    }
}

extension View {
    /// Binds `format` to `AppSettings.dateFormat` while the view is on screen.
    func zentaoDateFormat(_ deps: ZentaoDependencies, into format: Binding<String>) -> some View {
        modifier(ZentaoDateFormatWatch(deps: deps, dateFormat: format))
    }
}

/// The kind of a ZenTao ticket (`bug`, `task`, `story`, or ""), lower-cased.
func zentaoKind(_ t: Ticket) -> String { (t.externalType ?? "").lowercased() }

/// ZenTao reports unset id fields as "0" and unset text as empty; both read as "no value".
func zentaoIsEmptyValue(_ value: String) -> Bool {
    let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return v.isEmpty || v == "0" || v == "—"
}

/// The id of a link field, or nil when ZenTao reports it unset.
func zentaoLinkId(_ id: String?) -> String? {
    guard let id, !zentaoIsEmptyValue(id) else { return nil }
    return id.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// `name` when ZenTao gave one, else the bare `id`: an id means nothing to a reader next to a name.
func zentaoNameOr(_ name: String?, _ id: String?) -> String {
    let n = name?.trimmingCharacters(in: .whitespaces) ?? ""
    return n.isEmpty ? (id ?? "") : n
}

/// The non-empty values joined with " · " ("0" counts as empty).
func zentaoJoined(_ values: [String?]) -> String {
    values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != "0" }.joined(separator: " · ")
}

func zentaoHoursLoggedText(_ h: Double) -> String { appFormat("zentaoHoursLogged", "%1$@ h logged so far", zentaoHoursText(h)) }
func zentaoHoursTotalText(_ h: Double) -> String { appFormat("zentaoHoursTotal", "%1$@ h in total", zentaoHoursText(h)) }
