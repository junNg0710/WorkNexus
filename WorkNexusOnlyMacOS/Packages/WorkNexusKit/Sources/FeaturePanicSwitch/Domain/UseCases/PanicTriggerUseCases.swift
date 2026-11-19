import CoreDomain
import Foundation

/// Ported from: lib/features/panic_switch/domain/usecases/should_send_panic.dart
/// Whether the pet sends `trigger`'s sticker: the feature is on, the trigger has a chat and its last send is older than the
/// debounce time.
public struct ShouldSendPanic: Sendable {
    public init() {}

    public func callAsFunction(trigger: PanicTrigger, config: PanicSwitchConfig, now: Date, lastSentAt: Date? = nil) -> Bool {
        config.enabled && config.chatFor(trigger) != nil
            && DebounceGate.allows(last: lastSentAt, now: now, window: TimeInterval(config.debounceSeconds))
    }
}

/// Ported from: lib/features/panic_switch/domain/usecases/should_trigger_panic.dart
/// Whether an arriving `message` sets `trigger` off on this computer: its sticker, fresh, in its chat of `accountId`, from an
/// allowed sender (anyone but you, by default; anyone in the demo chat), and not within the debounce time of `trigger`'s
/// last run.
public struct ShouldTriggerPanic: Sendable {
    public init() {}

    public func callAsFunction(trigger: PanicTrigger, message: PanicIncomingMessage, config: PanicSwitchConfig,
                               accountId: String, now: Date, lastTriggeredAt: Date? = nil) -> Bool {
        guard config.enabled, !message.isMine, !message.deleted else { return false }
        guard let chatGid = config.chatFor(trigger), message.accountId == accountId, message.chatGid == chatGid else { return false }
        // The allowlist is the team group's; the demo chat is your own pick and accepts anyone.
        if trigger == .release, !config.anySender, !config.allowedSenderIds.contains(message.senderId) { return false }
        guard Self.triggerOf(message) == trigger else { return false }
        // Both ways: the sender's clock may run a little ahead of this one.
        guard abs(now.timeIntervalSince(message.sentAt)) <= PanicSwitchConstants.freshWindow else { return false }
        return DebounceGate.allows(last: lastTriggeredAt, now: now, window: TimeInterval(config.debounceSeconds))
    }

    /// The trigger `message` is the sticker of, if any: an image message under one of the reserved file names, in any case.
    /// Cheap: the listener checks it for every arriving message before anything else.
    public static func triggerOf(_ message: PanicIncomingMessage) -> PanicTrigger? {
        message.imageName.flatMap(PanicTrigger.ofSticker)
    }
}

/// Ported from: lib/features/panic_switch/domain/usecases/run_panic_switch.dart
/// Does what the switch is set to: hides every app but the ones to open, opens those (the first ends up in front), then
/// hides WorkNexus itself. Each step runs even when an earlier one fails — a half-done switch beats none; the first failure
/// is returned.
public struct RunPanicSwitch: Sendable {
    private let apps: AppSwitcher

    public init(_ apps: AppSwitcher) { self.apps = apps }

    public func callAsFunction(_ config: PanicSwitchConfig) async -> Outcome<Void> {
        var first: Failure?
        func keep(_ result: Outcome<Void>) { if first == nil { first = result.failure } }

        keep(await apps.hideOthers(keep: config.appsToOpen))
        // The last one opened is in front, so open the first last.
        for app in config.appsToOpen.reversed() { keep(await apps.activate(app)) }
        // WorkNexus is never one of the apps to open, so it hides too.
        keep(await apps.hideSelf())
        return first.map { .failure($0) } ?? .success(())
    }
}
