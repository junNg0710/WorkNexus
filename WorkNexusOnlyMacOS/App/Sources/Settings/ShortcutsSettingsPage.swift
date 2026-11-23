import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The keyboard shortcuts settings: the keys that open each place of the rail (⌘1 … ⌘0, then ⌥⌘1 … ⌥⌘0 from the top
/// unless the user chose others), a switch for the lot and a way back to how they came. Not in the Flutter app.
struct ShortcutsSettingsPage: View {
    let root: CompositionRoot

    var body: some View {
        let shell = root.shell, choices = shell.settings.railShortcuts
        let places = shell.railPlaces, keys = shell.railShortcuts
        SettingsPage(title: appString("shortcutsSettings", "Shortcuts")) {
            SettingsCard(title: appString("shortcutsRailTitle", "Places on the rail"),
                         subtitle: appString("shortcutsRailHint", "⌘1 to ⌘9 and ⌘0 open the first ten places from the top, ⌥⌘1 to ⌥⌘0 the next ten. Hold ⌘ to see the keys on the rail. Click a shortcut to choose other keys for that place.")) {
                SettingsToggleRow(label: appString("shortcutsRailEnabled", "Open places with the keyboard"), isOn: choices.enabled) { on in
                    shell.updateSettings { $0.railShortcuts.enabled = on }
                }
                if choices.enabled {
                    SettingsRow(label: appString("shortcutsResetHint", "Put every shortcut back to the keys of its position")) {
                        AppButton(appString("reset", "Reset"), systemImage: "arrow.counterclockwise") {
                            shell.updateSettings { $0.railShortcuts = RailShortcuts() }
                        }
                    }
                    ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                        SettingsRow(label: "\(index + 1). \(place.name)") {
                            ShortcutRecorder(shortcut: keys[place.id], problem: Self.problem) { new in
                                shell.updateSettings { $0.railShortcuts.assign(new, to: place.id, places: places.map(\.id)) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Why a key combination is refused, in the user's words.
    private static func problem(_ keys: KeyShortcut) -> String? {
        switch keys.problem {
        case .needsCommandOrControl: appString("shortcutNeedsModifier", "Hold ⌘ or ⌃ with it")
        case .reserved: appString("shortcutReserved", "WorkNexus already uses these keys")
        case nil: nil
        }
    }
}
