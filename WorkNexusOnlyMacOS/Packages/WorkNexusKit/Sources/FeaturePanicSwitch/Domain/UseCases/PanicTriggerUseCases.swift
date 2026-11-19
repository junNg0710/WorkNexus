import CoreDomain
import Foundation

/// Ported from: lib/features/panic_switch/domain/usecases/should_send_panic.dart
/// Whether a triple click on the floating button sends the sticker: a chat is chosen and the last send is older than the
/// debounce time.
public struct ShouldSendPanic: Sendable {
    public init() {}

    public func callAsFunction(config: PanicSwitchConfig, now: Date, lastSentAt: Date? = nil) -> Bool {
        config.sendChatGid != nil
            && DebounceGate.allows(last: lastSentAt, now: now, window: TimeInterval(config.debounceSeconds))
    }
}

/// Ported from: lib/features/panic_switch/domain/usecases/should_trigger_panic.dart
/// Whether an arriving `message` sets the panic switch off on this computer: the "Thầy vô" sticker, fresh, in the chosen
/// chat of `accountId`, from an allowed sender (anyone but you, by default), and not within the debounce time of the last
/// trigger.
public struct ShouldTriggerPanic: Sendable {
    public init() {}

    public func callAsFunction(message: PanicIncomingMessage, config: PanicSwitchConfig, accountId: String, now: Date,
                               lastTriggeredAt: Date? = nil) -> Bool {
        guard config.enabled, !message.isMine, !message.deleted else { return false }
        guard message.accountId == accountId, message.chatGid == config.receiveChatGid else { return false }
        if !config.anySender, !config.allowedSenderIds.contains(message.senderId) { return false }
        guard Self.isPanicSticker(message) else { return false }
        // Both ways: the sender's clock may run a little ahead of this one.
        guard abs(now.timeIntervalSince(message.sentAt)) <= PanicSwitchConstants.freshWindow else { return false }
        return DebounceGate.allows(last: lastTriggeredAt, now: now, window: TimeInterval(config.debounceSeconds))
    }

    /// The sticker is an image message under the reserved file name, in any case. Cheap: the listener checks it for every
    /// arriving message before anything else.
    public static func isPanicSticker(_ message: PanicIncomingMessage) -> Bool {
        message.imageName?.lowercased() == PanicSwitchConstants.stickerFileName
    }
}

/// Ported from: lib/features/panic_switch/domain/usecases/run_panic_switch.dart
/// Does what the switch is set to: brings the target app forward, hides the chosen apps, then WorkNexus itself. Each step
/// runs even when an earlier one fails — a half-done switch beats none; the first failure is returned.
public struct RunPanicSwitch: Sendable {
    private let apps: AppSwitcher

    public init(_ apps: AppSwitcher) { self.apps = apps }

    public func callAsFunction(_ config: PanicSwitchConfig) async -> Outcome<Void> {
        var first: Failure?
        func keep(_ result: Outcome<Void>) { if first == nil { first = result.failure } }

        let target = config.targetApp
        if let target { keep(await apps.activate(target)) }
        for app in config.appsToHide where app.id != target?.id { keep(await apps.hide(app)) }
        if config.hideSelf { keep(await apps.hideSelf()) }
        return first.map { .failure($0) } ?? .success(())
    }
}
