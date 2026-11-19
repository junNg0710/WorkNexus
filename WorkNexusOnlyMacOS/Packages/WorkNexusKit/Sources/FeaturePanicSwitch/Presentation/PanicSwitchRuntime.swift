import CoreDomain
import Foundation

/// Ported from: lib/features/panic_switch/presentation/providers/panic_switch_runtime.dart
/// Reacts to the two events of the panic switch: the sticker arriving (switch apps here) and the alert raised by three
/// clicks on the pet (send the sticker, then switch here too). Holds when each last happened, for the debounce.
@MainActor
public final class PanicSwitchRuntime {
    private let account: () -> Account?
    private let config: () -> PanicSwitchConfig?
    private let run: RunPanicSwitch
    private let send: SendPanicSticker
    private let clock: () -> Date
    private var lastTriggeredAt: Date?
    private var lastSentAt: Date?

    public init(account: @escaping () -> Account?, config: @escaping () -> PanicSwitchConfig?, run: RunPanicSwitch,
                send: SendPanicSticker, clock: @escaping () -> Date = Date.init) {
        self.account = account; self.config = config; self.run = run; self.send = send; self.clock = clock
    }

    /// Switches apps when `message` is the sticker this computer listens for.
    public func onIncoming(_ message: PanicIncomingMessage) async -> Outcome<Void> {
        guard let account = account(), let config = config() else { return .success(()) }
        let now = clock()
        let fire = ShouldTriggerPanic()(message: message, config: config, accountId: account.id, now: now,
                                        lastTriggeredAt: lastTriggeredAt)
        guard fire else { return .success(()) }
        lastTriggeredAt = now
        return await run(config)
    }

    /// The alert (three clicks on the pet): sends the sticker to the chosen chat, at most once per debounce time, and once
    /// it is sent switches apps here too — the one who raises it hides like everyone who receives it (your own message never
    /// comes back as incoming). Sent to yourself, it switches first, even with the chat server down, and sends after.
    public func onAlert() async -> Outcome<Void> {
        guard let account = account(), let config = config(), let chatGid = config.sendChatGid else { return .success(()) }
        let now = clock()
        guard ShouldSendPanic()(config: config, now: now, lastSentAt: lastSentAt) else { return .success(()) }
        lastSentAt = now
        if config.sendsToSelf {
            var switched: Outcome<Void> = .success(())
            if config.enabled { lastTriggeredAt = now; switched = await run(config) }
            let sent = await send(accountId: account.id, chatGid: chatGid)
            if case .failure = switched { return switched }
            return sent
        }
        let sent = await send(accountId: account.id, chatGid: chatGid)
        guard case .success = sent, config.enabled else { return sent }
        lastTriggeredAt = clock()
        return await run(config)
    }

    /// Switches apps now, as the sticker would, without any chat: the "Try" button in Settings.
    public func runNow() async -> Outcome<Void> {
        guard let config = config() else { return .success(()) }
        return await run(config)
    }
}
