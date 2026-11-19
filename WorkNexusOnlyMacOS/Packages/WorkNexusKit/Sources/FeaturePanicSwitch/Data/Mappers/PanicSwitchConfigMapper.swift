import Foundation

/// Ported from: lib/features/panic_switch/data/mappers/panic_switch_config_mapper.dart
/// `PanicSwitchConfig` ↔ the JSON it is stored as (the same object the Flutter app keeps, plus the pet's `petGesture` and
/// `petHoldSeconds`; the Flutter-only floating button look — `overlaySize`, `overlayOpacity`, `overlayGesture` — is not
/// kept). Unknown or missing fields fall back to the defaults, so older saved settings still load.
enum PanicSwitchConfigMapper {
    static func toJSON(_ c: PanicSwitchConfig) throws -> Data {
        let object: [String: Any] = [
            "enabled": c.enabled, "overlayVisible": c.overlayVisible, "chatGid": c.chatGid ?? NSNull(),
            "demoMode": c.demoMode, "demoChatGid": c.demoChatGid ?? NSNull(), "anySender": c.anySender,
            "allowedSenderIds": c.allowedSenderIds, "appsToOpen": c.appsToOpen.map(app),
            "debounceSeconds": c.debounceSeconds, "petGesture": c.petGesture.rawValue, "petHoldSeconds": c.petHoldSeconds,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func fromJSON(_ data: Data) -> PanicSwitchConfig {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return PanicSwitchConfig() }
        // Demo mode was test mode (`test…` keys). Before that, "send to myself" was saved as the one chat (`chatIsSelf`); it
        // is the demo chat now, and the team group is looked up again.
        let legacySelf = bool(json["chatIsSelf"]) == true
        let legacySelfGid = legacySelf ? json["chatGid"] as? String : nil
        // Test mode had a chat to send to and one to listen in; the listening one is kept (the one people picked a group
        // for), else the sending one.
        let send = json["testSendChatGid"] as? String ?? legacySelfGid
        let demoChatGid = json["demoChatGid"] as? String ?? json["testChatGid"] as? String
            ?? json["testReceiveChatGid"] as? String ?? send
        // Before the apps to open, there was one target app (and a list to hide, which is now everything else).
        let apps = json["appsToOpen"] as? [Any] ?? [json["targetApp"] as Any]
        var config = PanicSwitchConfig(
            enabled: bool(json["enabled"]) ?? true,
            overlayVisible: bool(json["overlayVisible"]) ?? true,
            chatGid: legacySelf ? nil : json["chatGid"] as? String,
            demoMode: bool(json["demoMode"]) ?? bool(json["testMode"]) ?? legacySelf,
            demoChatGid: demoChatGid,
            anySender: bool(json["anySender"]) ?? true,
            allowedSenderIds: (json["allowedSenderIds"] as? [Any] ?? []).compactMap(int),
            appsToOpen: apps.compactMap(readApp),
            debounceSeconds: int(json["debounceSeconds"]) ?? PanicSwitchConstants.defaultDebounceSeconds)
        config.petGesture = (json["petGesture"] as? String).flatMap(PanicPetGesture.init(rawValue:)) ?? .hold
        let range = PanicSwitchConstants.petHoldRange
        config.petHoldSeconds = min(max(int(json["petHoldSeconds"]) ?? PanicSwitchConstants.defaultPetHoldSeconds, range.lowerBound), range.upperBound)
        return config
    }

    private static func app(_ a: AppRef) -> [String: String] { ["id": a.id, "name": a.name] }

    private static func readApp(_ json: Any?) -> AppRef? {
        guard let o = json as? [String: Any], let id = o["id"] as? String, let name = o["name"] as? String else { return nil }
        return AppRef(id: id, name: name)
    }

    /// A JSON `true` / `false` (a number is not one, though Foundation would bridge it).
    private static func bool(_ v: Any?) -> Bool? {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    /// A JSON whole number (a boolean is not one).
    private static func int(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == n.doubleValue.rounded() else { return nil }
        return n.intValue
    }
}
