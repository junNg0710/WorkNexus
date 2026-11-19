/// Ported from: lib/features/panic_switch/domain/entities/app_ref.dart
/// An app on this Mac the switch can bring forward or hide, found by its bundle identifier (`id`).
public struct AppRef: Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// Ported from: lib/features/panic_switch/domain/entities/panic_switch_config.dart
/// This computer's panic switch settings. Kept per device: who may set it off here, and what it does, is each person's own
/// choice.
public struct PanicSwitchConfig: Hashable, Sendable {
    /// The feature on this computer: off, the pet does not set it off, and nothing is sent or acted on.
    public var enabled: Bool
    /// The pet sets it off (the setting the Flutter app keeps for its floating button).
    public var overlayVisible: Bool
    /// The team's group: where the official sticker is sent and listened for; picked by name (`PickDefaultPanicGroup`),
    /// nil until found.
    public var chatGid: String?
    /// Demo mode: a second trigger, beside the team's group, that sends and listens for the demo sticker in `demoChatGid`.
    public var demoMode: Bool
    public var demoChatGid: String?
    /// Anyone in the team's group (but you) may set the switch off here; when off, only `allowedSenderIds` may. The demo
    /// chat accepts anyone.
    public var anySender: Bool
    /// Chat user ids whose sticker sets the switch off here when not `anySender`. Empty = nobody.
    public var allowedSenderIds: [Int]
    /// Opened or brought forward when the switch goes off, the first in front; every other running app is hidden.
    public var appsToOpen: [AppRef]
    /// The least time between two triggers, sending or receiving (each trigger counts its own).
    public var debounceSeconds: Int
    /// How the pet sets off the official trigger (macOS only: the Flutter app has its floating button instead).
    public var petGesture: PanicPetGesture = .hold
    /// How long the pet is held for it, in seconds (`PanicSwitchConstants.petHoldRange`).
    public var petHoldSeconds: Int = PanicSwitchConstants.defaultPetHoldSeconds

    public init(enabled: Bool = true, overlayVisible: Bool = true, chatGid: String? = nil, demoMode: Bool = false,
                demoChatGid: String? = nil, anySender: Bool = true, allowedSenderIds: [Int] = [], appsToOpen: [AppRef] = [],
                debounceSeconds: Int = PanicSwitchConstants.defaultDebounceSeconds) {
        self.enabled = enabled; self.overlayVisible = overlayVisible; self.chatGid = chatGid; self.demoMode = demoMode
        self.demoChatGid = demoChatGid; self.anySender = anySender; self.allowedSenderIds = allowedSenderIds
        self.appsToOpen = appsToOpen; self.debounceSeconds = debounceSeconds
    }

    /// Where `trigger`'s sticker is sent and listened for; nil when it is off.
    public func chatFor(_ trigger: PanicTrigger) -> String? {
        switch trigger {
        case .release: chatGid
        case .demo: demoMode ? demoChatGid : nil
        }
    }
}

/// How the pet sets off the official trigger: pressed and held for a few seconds (the default: hard to do by accident), or
/// clicked two or three times quickly (upstream's `PanicGesture` of its floating button). Not in the Flutter app.
public enum PanicPetGesture: String, Sendable, CaseIterable, Equatable {
    case doubleClick
    case tripleClick
    case hold
}
