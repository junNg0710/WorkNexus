import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// How the pet moves on its own: how often it walks off, whether it waves and looks around while idle, whether it turns
/// toward the pointer, and - on the desktop - how far it walks. Not in the Flutter app.
struct PetMotionCard: View {
    let shell: ShellModel

    var body: some View {
        let s = shell.settings, b = s.petBehavior
        SettingsCard(title: appString("petCardMotion", "Movement")) {
            SettingsRow(label: appString("petActivity", "How active it is")) {
                SettingsSegmented(values: [(.still, appString("petActivityStill", "Stands still")),
                                           (.calm, appString("petActivityCalm", "Calm")),
                                           (.normal, appString("petActivityNormal", "Normal")),
                                           (.lively, appString("petActivityLively", "Lively"))] as [(PetActivity, String)],
                                  value: b.activity) { v in shell.updateSettings { $0.petBehavior.activity = v; $0.petBehavior.resumeActivity = nil } }
            }
            if s.petDisplay == .floating, b.activity.wanders {
                SettingsRow(label: appString("petRoam", "Where it walks")) {
                    SettingsSegmented(values: [(.nearby, appString("petRoamNearby", "Around its spot")),
                                               (.screen, appString("petRoamScreen", "Across the screen"))] as [(PetRoam, String)],
                                      value: b.roam) { v in shell.updateSettings { $0.petBehavior.roam = v } }
                }
            }
            SettingsToggleRow(label: appString("petIdleGestures", "Waves and looks around when idle"), isOn: b.idleGestures) { on in
                shell.updateSettings { $0.petBehavior.idleGestures = on }
            }
            SettingsToggleRow(label: appString("petFollowsCursor", "Looks toward the pointer (pets that can)"), isOn: s.petFollowsCursor) { on in
                shell.updateSettings { $0.petFollowsCursor = on }
            }
        }
    }
}

/// What the pet reacts to, and whether, what and how long it speaks.
struct PetReactionsCard: View {
    let shell: ShellModel

    /// The events, in the order listed, with their names.
    private var events: [(PetEvent, String)] {
        [(.chat, appString("petReactChat", "New chat messages")),
         (.notifications, appString("petReactNotifications", "ZenTao notifications")),
         (.apps, appString("petReactApps", "News from the apps on the rail")),
         (.sync, appString("petReactSync", "Sync status (syncing, errors, offline)")),
         (.celebration, appString("petReactCelebration", "A ticket you resolved"))]
    }

    var body: some View {
        let s = shell.settings, b = s.petBehavior
        SettingsCard(title: appString("petCardReactions", "Reactions and speech"),
                     subtitle: appString("petReactsHint", "What the pet reacts to.")) {
            ForEach(events, id: \.0) { event, name in
                SettingsToggleRow(label: name, isOn: !b.ignored.contains(event)) { on in
                    shell.updateSettings { if on { $0.petBehavior.ignored.remove(event) } else { $0.petBehavior.ignored.insert(event) } }
                }
            }
            Divider()
            SettingsToggleRow(label: appString("petSpeaks", "Says what it reacts to in a speech bubble"), isOn: b.speaks) { on in
                shell.updateSettings { $0.petBehavior.speaks = on }
            }
            if b.speaks {
                SettingsToggleRow(label: appString("petShowsDetails", "Says what a new message or notification says"),
                                  isOn: s.petShowsDetails) { on in
                    shell.updateSettings { $0.petShowsDetails = on }
                }
                SettingsRow(label: appString("petSpeechLength", "How long a line stays")) {
                    SettingsSegmented(values: [(.short, appString("petSpeechShort", "Short")),
                                               (.normal, appString("petSpeechNormal", "Medium")),
                                               (.long, appString("petSpeechLong", "Long"))] as [(PetSpeechLength, String)],
                                      value: b.speechLength) { v in shell.updateSettings { $0.petBehavior.speechLength = v } }
                }
            }
            SettingsToggleRow(label: appString("petStatusOnHover", "Says how things are when the pointer rests on it"),
                              isOn: b.statusOnHover) { on in
                shell.updateSettings { $0.petBehavior.statusOnHover = on }
            }
        }
    }
}
