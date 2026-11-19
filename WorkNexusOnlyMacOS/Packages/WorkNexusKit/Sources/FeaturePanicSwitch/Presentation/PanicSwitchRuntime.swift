import CoreDomain
import Foundation

/// Ported from: lib/features/panic_switch/presentation/providers/panic_switch_runtime.dart
/// Reacts to the two events of the panic switch: a sticker arriving (switch apps here) and the pet setting it off (switch
/// here, then send the sticker), for each `PanicTrigger` side by side. Holds when each last happened, per trigger, for the
/// debounce.
@MainActor
public final class PanicSwitchRuntime {
    private let account: () -> Account?
    private let config: () -> PanicSwitchConfig?
    private let run: RunPanicSwitch
    private let send: SendPanicSticker
    private let clock: () -> Date
    private var lastTriggeredAt: [PanicTrigger: Date] = [:]
    private var lastSentAt: [PanicTrigger: Date] = [:]

    public init(account: @escaping () -> Account?, config: @escaping () -> PanicSwitchConfig?, run: RunPanicSwitch,
                send: SendPanicSticker, clock: @escaping () -> Date = Date.init) {
        self.account = account; self.config = config; self.run = run; self.send = send; self.clock = clock
    }

    /// Switches apps when `message` is a sticker this computer listens for.
    public func onIncoming(_ message: PanicIncomingMessage) async -> Outcome<Void> {
        guard let account = account(), let config = config(), let trigger = ShouldTriggerPanic.triggerOf(message) else {
            return .success(())
        }
        let now = clock()
        let fire = ShouldTriggerPanic()(trigger: trigger, message: message, config: config, accountId: account.id, now: now,
                                        lastTriggeredAt: lastTriggeredAt[trigger])
        guard fire else { return .success(()) }
        lastTriggeredAt[trigger] = now
        return await run(config)
    }

    /// Sends `trigger`'s sticker to its chat and switches apps here too, at most once per debounce time (the pet's gesture:
    /// `.release`; "Demo" in its right-click menu: `.demo`). Switching comes first, so it works even with the chat server
    /// down; a send failure is still reported.
    public func onPetTriggered(_ trigger: PanicTrigger) async -> Outcome<Void> {
        guard let account = account(), let config = config(), let chatGid = config.chatFor(trigger) else { return .success(()) }
        let now = clock()
        guard ShouldSendPanic()(trigger: trigger, config: config, now: now, lastSentAt: lastSentAt[trigger]) else {
            return .success(())
        }
        lastSentAt[trigger] = now
        lastTriggeredAt[trigger] = now
        let switched = await run(config)
        let sent = await send(trigger: trigger, accountId: account.id, chatGid: chatGid)
        if case .failure = switched { return switched }
        return sent
    }
}
