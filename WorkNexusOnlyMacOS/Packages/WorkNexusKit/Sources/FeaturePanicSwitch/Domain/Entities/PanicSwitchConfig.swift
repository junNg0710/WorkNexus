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
    /// React to the sticker arriving.
    public var enabled: Bool
    /// Show the floating button that sends the sticker.
    public var overlayVisible: Bool
    /// The team's group: where the sticker is sent and listened for; picked by name (`PickDefaultPanicGroup`), nil until found.
    public var chatGid: String?
    /// Test mode: the sticker is sent to and listened for in `testChatGid` instead of the team's group, to try the switch
    /// without bothering anyone.
    public var testMode: Bool
    public var testChatGid: String?
    /// `testChatGid` is the user's own chat ("My Cloud"): sending there switches apps on this computer, as the user's own
    /// messages never come back as incoming.
    public var testChatIsSelf: Bool
    /// Anyone in the chat (but you) may set the switch off here; when off, only `allowedSenderIds` may.
    public var anySender: Bool
    /// Chat user ids whose sticker sets the switch off here when not `anySender`. Empty = nobody.
    public var allowedSenderIds: [Int]
    /// Brought to the front when the switch goes off.
    public var targetApp: AppRef?
    public var appsToHide: [AppRef]
    /// Also hide WorkNexus itself.
    public var hideSelf: Bool
    /// The least time between two triggers, sending or receiving.
    public var debounceSeconds: Int
    /// How the pet raises the alert (macOS only: the Flutter app has its floating button instead).
    public var petGesture: PanicPetGesture = .hold
    /// How long the pet is held for the alert, in seconds (`PanicSwitchConstants.petHoldRange`).
    public var petHoldSeconds: Int = PanicSwitchConstants.defaultPetHoldSeconds

    public init(enabled: Bool = true, overlayVisible: Bool = true, chatGid: String? = nil, testMode: Bool = false,
                testChatGid: String? = nil, testChatIsSelf: Bool = false, anySender: Bool = true, allowedSenderIds: [Int] = [],
                targetApp: AppRef? = nil, appsToHide: [AppRef] = [], hideSelf: Bool = true,
                debounceSeconds: Int = PanicSwitchConstants.defaultDebounceSeconds) {
        self.enabled = enabled; self.overlayVisible = overlayVisible; self.chatGid = chatGid; self.testMode = testMode
        self.testChatGid = testChatGid; self.testChatIsSelf = testChatIsSelf; self.anySender = anySender
        self.allowedSenderIds = allowedSenderIds; self.targetApp = targetApp; self.appsToHide = appsToHide
        self.hideSelf = hideSelf; self.debounceSeconds = debounceSeconds
    }

    /// Where the floating button sends the sticker.
    public var sendChatGid: String? { testMode ? testChatGid : chatGid }
    /// Sending switches apps on this computer too (test mode, to yourself).
    public var sendsToSelf: Bool { testMode && testChatIsSelf }
    /// Where an arriving sticker sets the switch off.
    public var receiveChatGid: String? { testMode ? testChatGid : chatGid }
}

/// How the pet raises the alert: pressed and held for a few seconds (the default: hard to do by accident), or clicked
/// three times quickly. Not in the Flutter app.
public enum PanicPetGesture: String, Sendable, CaseIterable, Equatable {
    case hold
    case tripleClick
}
