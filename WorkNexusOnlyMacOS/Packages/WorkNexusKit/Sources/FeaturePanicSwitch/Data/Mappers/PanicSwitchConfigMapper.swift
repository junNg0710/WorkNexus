import Foundation

/// Ported from: lib/features/panic_switch/data/mappers/panic_switch_config_mapper.dart
/// `PanicSwitchConfig` ↔ the JSON it is stored as (the same object the Flutter app keeps). Unknown or missing fields fall
/// back to the defaults, so older saved settings still load.
enum PanicSwitchConfigMapper {
    static func toJSON(_ c: PanicSwitchConfig) throws -> Data {
        let object: [String: Any] = [
            "enabled": c.enabled, "overlayVisible": c.overlayVisible, "chatGid": c.chatGid ?? NSNull(),
            "testMode": c.testMode, "testChatGid": c.testChatGid ?? NSNull(), "testChatIsSelf": c.testChatIsSelf,
            "anySender": c.anySender, "allowedSenderIds": c.allowedSenderIds,
            "targetApp": c.targetApp.map(app) ?? NSNull(), "appsToHide": c.appsToHide.map(app),
            "hideSelf": c.hideSelf, "debounceSeconds": c.debounceSeconds,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func fromJSON(_ data: Data) -> PanicSwitchConfig {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return PanicSwitchConfig() }
        // Before test mode, "send to myself" was saved as the one chat (`chatIsSelf`); it is test mode's chat now, and the
        // team group is looked up again.
        let legacySelf = bool(json["chatIsSelf"]) == true
        let legacySelfGid = legacySelf ? json["chatGid"] as? String : nil
        // Test mode had a chat to send to and one to listen in; the listening one is kept (the one people picked a group
        // for), else the sending one.
        let send = json["testSendChatGid"] as? String ?? legacySelfGid
        let testChatGid = json["testChatGid"] as? String ?? json["testReceiveChatGid"] as? String ?? send
        let testChatIsSelf = bool(json["testChatIsSelf"])
            ?? (testChatGid != nil && testChatGid == send && (bool(json["testSendToSelf"]) == true || legacySelf))
        return PanicSwitchConfig(
            enabled: bool(json["enabled"]) ?? true,
            overlayVisible: bool(json["overlayVisible"]) ?? true,
            chatGid: legacySelf ? nil : json["chatGid"] as? String,
            testMode: bool(json["testMode"]) ?? legacySelf,
            testChatGid: testChatGid,
            testChatIsSelf: testChatIsSelf,
            anySender: bool(json["anySender"]) ?? true,
            allowedSenderIds: (json["allowedSenderIds"] as? [Any] ?? []).compactMap(int),
            targetApp: readApp(json["targetApp"]),
            appsToHide: (json["appsToHide"] as? [Any] ?? []).compactMap(readApp),
            hideSelf: bool(json["hideSelf"]) ?? true,
            debounceSeconds: int(json["debounceSeconds"]) ?? PanicSwitchConstants.defaultDebounceSeconds)
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
