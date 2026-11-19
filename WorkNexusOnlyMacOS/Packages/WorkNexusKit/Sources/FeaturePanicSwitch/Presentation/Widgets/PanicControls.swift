import CoreUI
import SwiftUI

/// Saves a change to the settings (the card says so when it could not be kept).
/// Ported from: lib/features/panic_switch/presentation/widgets/panic_switch_save.dart
typealias PanicSave = (@escaping (inout PanicSwitchConfig) -> Void) -> Void

/// Picks one of `chats` (the demo chat), by title, with a search box.
/// Ported from: lib/features/panic_switch/presentation/widgets/panic_chat_picker.dart
struct PanicChatPicker: View {
    let chats: [PanicChat]
    let value: String?
    let onChanged: (PanicChat) -> Void

    var body: some View {
        SearchableDropdownField(items: chats, value: chats.first { $0.chat.gid == value }, labelOf: \.title,
                                hintText: appString("panicSwitchGroupPick", "Pick a chat"),
                                searchHint: appString("panicSwitchSearch", "Search…"),
                                emptyLabel: appString("panicSwitchNoMatches", "No matches"), onChanged: onChanged)
    }
}

/// The debounce choices (with the saved one among them when the card does not offer it).
/// Ported from: lib/features/panic_switch/presentation/widgets/panic_behaviour_sections.dart
struct PanicDebounceSection: View {
    let config: PanicSwitchConfig
    let save: PanicSave

    var body: some View {
        let seconds = config.debounceSeconds
        let choices = Set(PanicSwitchConstants.debounceChoices + [seconds]).sorted()
        AppExpandableCardSection(title: appString("panicSwitchDebounceLabel", "Don't go off again within"),
                                 hint: appString("panicSwitchDebounceHint", "Sending and switching both happen at most once in this time."),
                                 content: {
            AppSegmentedTabs(choices.map { s in
                AppSegmentedTab(label: appFormat("panicSwitchSeconds", "%1$@s", "\(s)"), active: seconds == s) {
                    save { $0.debounceSeconds = s }
                }
            })
            .fixedSize()
        })
    }
}

/// An on/off switch beside a section's title.
struct PanicToggle: View {
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: onChange)).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}

/// A line of explanation in place of a list.
struct PanicNote: View {
    @Environment(\.appTheme) private var theme
    let text: String

    var body: some View {
        Text(text).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2).fixedSize(horizontal: false, vertical: true)
    }
}
