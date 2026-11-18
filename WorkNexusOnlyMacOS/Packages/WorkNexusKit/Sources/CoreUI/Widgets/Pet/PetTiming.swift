import Foundation

/// How long each frame of a pet's animations shows. Not in the Flutter app.
///
/// - `steady`: one pace per animation, what the bundled TBChat character was drawn for.
/// - `codex`: the per-frame timings of the Codex pet format (`hatch-pet` `references/animation-rows.md`), which pets
///   downloaded from codex-pets.net are drawn for: most rows hold their last frame a little longer.
public enum PetTiming: Sendable, Equatable {
    case steady, codex

    /// How long frame `index` of `animation` shows (it wraps, like the frames do).
    public func duration(_ animation: PetAnimation, frame index: Int) -> TimeInterval {
        switch self {
        case .steady: return animation.frameDuration
        case .codex:
            let all = Self.codexMilliseconds(animation)
            return all[((index % all.count) + all.count) % all.count] / 1000
        }
    }

    /// The Codex timings, in milliseconds, one per frame of the row.
    static func codexMilliseconds(_ animation: PetAnimation) -> [Double] {
        switch animation {
        case .idle: [280, 110, 110, 140, 140, 320]
        case .runningRight, .runningLeft: Array(repeating: 120, count: 7) + [220]
        case .waving: Array(repeating: 140, count: 3) + [280]
        case .jumping: Array(repeating: 140, count: 4) + [280]
        case .failed: Array(repeating: 140, count: 7) + [240]
        case .waiting: Array(repeating: 150, count: 5) + [260]
        case .running: Array(repeating: 120, count: 5) + [220]
        case .review: Array(repeating: 150, count: 5) + [280]
        }
    }
}
