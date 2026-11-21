import Foundation

/// Ported from: lib/features/panic_switch/domain/panic_switch_constants.dart
/// Fixed facts of the panic switch ("Thầy vô"). Shared with the Flutter app: both send and recognise the same sticker.
public enum PanicSwitchConstants {
    /// The file name the sticker is sent under. The chat server gives every upload a new id and carries no sticker
    /// identity, so this reserved name is what receivers recognise it by.
    public static let stickerFileName = "worknexus-thayvo-v1.png"
    /// The demo trigger's sticker: the same picture under another name, so a demo never sets off the team's switch.
    public static let demoStickerFileName = "worknexus-thayvo-demo-v1.png"
    public static let stickerMimeType = "image/png"
    /// The feature is only offered to people signed in to this ZenTao.
    public static let zentaoBaseUrl = "https://zentao.oasoft.xyz:4433/zentao"
    /// The team's group: picked by default until the user chooses one, and who the feature is for at all. Someone not in
    /// it (a manager trying the app) sees nothing of the switch: no settings page, no trigger on the pet, no listening.
    public static let defaultGroupName = "VN Mobile Tester"
    /// A sticker older than this is ignored: a guard against messages that arrive late (after a reconnect) setting the
    /// switch off long after.
    public static let freshWindow: TimeInterval = 30
    public static let defaultDebounceSeconds = 60
    /// How long the pet is held for the alert by default, and the range the user can set (macOS only).
    public static let defaultPetHoldSeconds = 3
    public static let petHoldRange = 1...30
    /// The debounce choices offered in Settings, in seconds (panic_switch_settings_card.dart `_debounceChoices`).
    public static let debounceChoices = [15, 30, 60, 120, 300]
}

/// Ported from: lib/features/panic_switch/domain/value_objects/debounce_gate.dart
/// Whether something last done at `last` may happen again at `now`, given it may happen at most once per `window` seconds.
public enum DebounceGate {
    public static func allows(last: Date?, now: Date, window: TimeInterval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= window
    }
}

/// Counts clicks on the floating button and says when three came in a row, each within `maxGap` of the one before
/// (the Flutter runner read AppKit's `clickCount == 3`; here the rule is a value of its own, so it can be tested).
/// A completed run starts over: a fourth quick click begins a new count.
public struct TripleClickCounter: Sendable {
    public let maxGap: TimeInterval
    public let needed: Int
    private var count = 0
    private var last: Date?

    public init(maxGap: TimeInterval = 0.5, needed: Int = 3) { self.maxGap = maxGap; self.needed = needed }

    /// Counts a click made at `date`; true when it completes the run.
    public mutating func click(at date: Date) -> Bool {
        if let last, date >= last, date.timeIntervalSince(last) <= maxGap { count += 1 } else { count = 1 }
        last = date
        guard count >= needed else { return false }
        count = 0; last = nil
        return true
    }
}
