/// Not in the Flutter app.
import Foundation

/// How much the pet moves about on its own.
public enum PetActivity: String, Codable, Sendable, CaseIterable {
    case still, calm, normal, lively

    /// Whether it walks off to another spot now and then.
    public var wanders: Bool { self != .still }

    /// The seconds it stands about before it does something of its own (a walk, a wave).
    public var pause: ClosedRange<Double> {
        switch self {
        case .still, .normal: 8...20
        case .calm: 30...60
        case .lively: 4...10
        }
    }
}

/// Where the pet on the desktop walks: a strip around the spot it was put, or the whole width of the screen.
public enum PetRoam: String, Codable, Sendable { case nearby, screen }

/// How long a line stays in the pet's speech bubble.
public enum PetSpeechLength: String, Codable, Sendable, CaseIterable {
    case short, normal, long

    /// What a line's usual time is multiplied by.
    public var factor: Double {
        switch self {
        case .short: 2.0 / 3
        case .normal: 1
        case .long: 5.0 / 3
        }
    }
}

/// The things going on in the app that the pet reacts to.
public enum PetEvent: String, Codable, Sendable, CaseIterable {
    /// A new chat message.
    case chat
    /// ZenTao notifications waiting for the user.
    case notifications
    /// News from an app on the rail (a Mac app's Dock badge, a web mini app's notification).
    case apps
    /// The accounts syncing, failing, or offline.
    case sync
    /// A ticket the user resolved.
    case celebration
}

/// What the pet does, as the user wants it: how much it moves, what it reacts to, and whether and how long it speaks.
public struct PetBehavior: Codable, Equatable, Sendable {
    public var activity = PetActivity.normal
    /// What it went back to moving like when "Stand still" in its menu is taken off again.
    public var resumeActivity: PetActivity?
    /// Whether a calm pet waves or looks things over now and then.
    public var idleGestures = true
    public var roam = PetRoam.nearby
    /// The events it does not react to: kept as the ones turned off, so an event added later is reacted to.
    public var ignored: Set<PetEvent> = []
    /// Whether it says what it reacts to in a speech bubble.
    public var speaks = true
    public var speechLength = PetSpeechLength.normal
    /// Whether it says how things are while the pointer rests on it.
    public var statusOnHover = true
    /// Until when it keeps quiet ("Quiet for 1 hour" in its menu); nil: it does not.
    public var quietUntil: Date?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var b = PetBehavior()
        b.activity = c.value(.activity, default: b.activity)
        b.resumeActivity = c.value(.resumeActivity, default: b.resumeActivity)
        b.idleGestures = c.value(.idleGestures, default: b.idleGestures)
        b.roam = c.value(.roam, default: b.roam)
        b.ignored = c.value(.ignored, default: b.ignored)
        b.speaks = c.value(.speaks, default: b.speaks)
        b.speechLength = c.value(.speechLength, default: b.speechLength)
        b.statusOnHover = c.value(.statusOnHover, default: b.statusOnHover)
        b.quietUntil = c.value(.quietUntil, default: b.quietUntil)
        self = b
    }

    /// "Stand still" in the pet's menu, and back again: it then moves about as it did before.
    public mutating func toggleStandingStill() {
        if activity == .still {
            activity = resumeActivity ?? .normal; resumeActivity = nil
        } else {
            resumeActivity = activity; activity = .still
        }
    }
}
