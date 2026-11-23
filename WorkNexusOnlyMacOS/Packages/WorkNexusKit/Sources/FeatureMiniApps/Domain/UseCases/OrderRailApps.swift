/// Not in the Flutter app. The websites and the Mac apps as the one list the rail shows, by position. Two at the same
/// position (never, once the order was saved) stay as given: websites before Mac apps.
public struct OrderRailApps: Sendable {
    public init() {}

    public func callAsFunction(miniApps: [MiniApp], nativeApps: [NativeApp]) -> [RailAppRef] {
        let entries = miniApps.map { (ref: RailAppRef.miniApp($0.id), position: $0.position) }
            + nativeApps.map { (ref: RailAppRef.nativeApp($0.id), position: $0.position) }
        return entries.enumerated()
            .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
            .map(\.element.ref)
    }
}
