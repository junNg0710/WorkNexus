import CoreDomain

/// Not in the Flutter app. The one order the websites and the Mac apps share on the rail (`MiniApp.position` and
/// `NativeApp.position` count in the same sequence), kept on this device.
public protocol RailOrderRepository: Sendable {
    /// Puts the websites and Mac apps in the order of `refs` on the rail, first to last, in one write. Touches nothing but
    /// their positions.
    func saveOrder(_ refs: [RailAppRef]) async -> Outcome<Void>
    /// The position after the last thing on the rail, website or Mac app: where a new one goes.
    func nextPosition() async -> Outcome<Int>
}
