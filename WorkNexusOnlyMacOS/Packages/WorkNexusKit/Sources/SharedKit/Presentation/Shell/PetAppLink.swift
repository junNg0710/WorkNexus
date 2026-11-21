/// Not in the Flutter app.

/// What a click on the pet's line about a rail app opens: `nativeapp:<id>` (a Mac app) or `miniapp:<id>` (a web mini app).
public enum PetAppLink: Equatable {
    case nativeApp(String)
    case miniApp(String)

    public static func nativeApp(_ id: String) -> String { "nativeapp:\(id)" }
    public static func miniApp(_ id: String) -> String { "miniapp:\(id)" }

    public init?(_ link: String) {
        if link.hasPrefix("nativeapp:") { self = .nativeApp(String(link.dropFirst("nativeapp:".count))) }
        else if link.hasPrefix("miniapp:") { self = .miniApp(String(link.dropFirst("miniapp:".count))) }
        else { return nil }
    }
}
