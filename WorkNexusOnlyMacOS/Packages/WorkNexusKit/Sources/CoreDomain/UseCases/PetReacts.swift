/// Not in the Flutter app.
import Foundation

/// What the pet reacts to and says now, from how the user set it (`PetBehavior`).
public struct PetReacts: Sendable {
    public let behavior: PetBehavior
    public let now: Date

    public init(_ behavior: PetBehavior, now: Date = Date()) {
        self.behavior = behavior; self.now = now
    }

    /// Told to keep quiet for a while ("Quiet for 1 hour"), and the while is not over.
    public var isQuiet: Bool { behavior.quietUntil.map { now < $0 } ?? false }

    /// Whether it reacts to `event`: not one the user turned off, and not while it keeps quiet.
    public func to(_ event: PetEvent) -> Bool { !isQuiet && !behavior.ignored.contains(event) }

    /// Whether it says things in its speech bubble.
    public var speaks: Bool { behavior.speaks && !isQuiet }

    /// How long a line that usually stays `usual` seconds stays.
    public func seconds(_ usual: TimeInterval) -> TimeInterval { usual * behavior.speechLength.factor }
}
