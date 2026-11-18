import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The privacy mode's shortcut: a menu command (View ▸ Privacy mode), so it works wherever focus is in the app.
/// Ported from: lib/features/chat/presentation/widgets/chat_privacy_shortcut.dart
enum ChatPrivacyShortcut {
    static let key: KeyEquivalent = "h"
    static let modifiers: EventModifiers = [.command, .shift]
    /// As shown to the user.
    static let label = "⌘⇧H"
}

/// The chat's privacy settings: the privacy mode (hiding chats on screen) with the parts it hides, and whether chat peers see
/// when the user is typing. Shown in Quick Settings ▸ Chat and on the Chat settings page.
/// Ported from: lib/features/chat/presentation/widgets/chat_privacy_settings.dart
struct ChatPrivacySettingsRows: View {
    let shell: ShellModel

    var body: some View {
        let privacy = shell.settings.chatPrivacy
        SettingsToggleRow(label: appString("chatPrivacyMode", "Privacy mode"),
                          hint: appFormat("chatPrivacyModeHint", "Hides chats on screen until you point at them, for a shared screen or a look over your shoulder: names and previews turn into dots, avatars into a placeholder, messages fade out. Nothing stored or sent changes. Shortcut: %1$@.", ChatPrivacyShortcut.label),
                          isOn: privacy.enabled) { on in shell.updateSettings { $0.chatPrivacy.enabled = on } }
        // The parts mean nothing while the mode is off.
        Group {
            SettingsToggleRow(label: appString("chatHidePreviews", "Hide message previews"),
                              hint: appString("chatHidePreviewsHint", "The last message under each chat in the list shows as dots."),
                              isOn: privacy.hidePreviews) { on in shell.updateSettings { $0.chatPrivacy.hidePreviews = on } }
            SettingsToggleRow(label: appString("chatHideIdentities", "Hide chat names and avatars"),
                              hint: appString("chatHideIdentitiesHint", "In the chat list, at the top of the open chat and in its message box."),
                              isOn: privacy.hideIdentities) { on in shell.updateSettings { $0.chatPrivacy.hideIdentities = on } }
            SettingsToggleRow(label: appString("chatHideMessages", "Fade out messages"),
                              hint: appString("chatHideMessagesHint", "Every message in the open chat, its threads and pins."),
                              isOn: privacy.hideMessages) { on in shell.updateSettings { $0.chatPrivacy.hideMessages = on } }
        }
        .disabled(!privacy.enabled)
        SettingsToggleRow(label: appString("chatSendTypingStatus", "Show when I'm typing"),
                          hint: appString("chatSendTypingStatusHint", "People in one-to-one and group chats see when you are typing a message."),
                          isOn: shell.settings.chatSendTypingStatus) { on in shell.updateSettings { $0.chatSendTypingStatus = on } }
    }
}
