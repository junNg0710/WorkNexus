import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/editor_date_input.dart
/// A ZenTao form date (`yyyy-MM-dd`, empty for none) in the app's date field: clearable, with quick picks for the
/// usual deadlines.
struct EditorDateInput: View {
    let value: String
    let onChanged: (String) -> Void

    var body: some View {
        AppDateField(value: FormValueFormat.date(value), clearable: true) { onChanged(FormValueFormat.dateText($0)) }
    }
}
