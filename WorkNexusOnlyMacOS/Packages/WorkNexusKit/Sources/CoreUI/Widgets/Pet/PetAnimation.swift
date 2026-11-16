import Foundation

/// The animations of the TBChat character, one row each of its sprite sheet (8 cells of 192 x 208 per row, the unused
/// ones empty). Not in the Flutter app.
public enum PetAnimation: String, CaseIterable, Sendable {
    case idle, runningRight, runningLeft, waving, jumping, failed, waiting, running, review

    /// The row of the sheet.
    public var row: Int {
        switch self {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        case .waving: 3
        case .jumping: 4
        case .failed: 5
        case .waiting: 6
        case .running: 7
        case .review: 8
        }
    }

    /// How many cells of the row are frames.
    public var frames: Int {
        switch self {
        case .idle, .waiting, .running, .review: 6
        case .runningRight, .runningLeft, .failed: 8
        case .waving: 4
        case .jumping: 5
        }
    }

    /// How long each frame shows.
    public var frameDuration: TimeInterval {
        switch self {
        case .idle: 0.32
        case .runningRight, .runningLeft: 0.09
        case .waving: 0.2
        case .jumping: 0.14
        case .failed: 0.16
        case .waiting: 0.28
        case .running: 0.16
        case .review: 0.2
        }
    }

    /// Plays once and goes back to what the character was doing (a gesture), rather than looping.
    public var isGesture: Bool { self == .waving || self == .jumping || self == .review || self == .failed }
}
