import Foundation
import Observation

/// What the TBChat character is doing: which animation and frame, and where it stands. It idles, waves when poked, jumps
/// when something is celebrated, shows how the app is doing (working / offline / in trouble), and now and then walks to
/// another spot or does a little something. The view drives it with `tick()` once per frame (`frameDuration`).
@MainActor @Observable
public final class PetDirector {
    /// How the app is doing, which sets what the character does when nothing else is going on.
    public enum Mood: Equatable, Sendable { case calm, busy, offline, trouble }

    public private(set) var animation: PetAnimation = .idle
    public private(set) var frame = 0
    /// Where the character stands: 0...1 across the room it has, left to right, and 0 (top) to 1 (bottom).
    public var x = 0.92
    public var y = 1.0
    public var mood: Mood = .calm { didSet { if mood != oldValue { moodChanged() } } }
    /// With reduced motion the character keeps still: its first frame, no walking, no gestures.
    public var reduceMotion = false

    /// How far it walks per second, as a fraction of the room.
    static let walkSpeed = 0.12
    /// Seconds of idling before it does something of its own.
    static let flourishAfter: ClosedRange<Double> = 18...40

    @ObservationIgnored private var walkTarget: Double?
    @ObservationIgnored private var idleFor = 0.0
    @ObservationIgnored private var nextFlourish: Double
    @ObservationIgnored private var gestureCycles = 0
    @ObservationIgnored private let random: () -> Double

    public init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
        nextFlourish = Self.flourishAfter.lowerBound + random() * (Self.flourishAfter.upperBound - Self.flourishAfter.lowerBound)
    }

    public var frameDuration: TimeInterval { animation.frameDuration }
    public var isWalking: Bool { animation == .runningLeft || animation == .runningRight }

    // MARK: Things that happen to it

    /// Poked (a click): waves.
    public func poke() { guard !reduceMotion else { return }; gesture(.waving, cycles: 1) }

    /// Something to celebrate (a bug resolved): jumps for joy.
    public func celebrate() { guard !reduceMotion else { return }; gesture(.jumping, cycles: 2) }

    /// Dragged to a spot: stays there.
    public func place(x: Double, y: Double) {
        self.x = min(max(x, 0), 1); self.y = min(max(y, 0), 1)
        walkTarget = nil
        if isWalking { setBase() }
    }

    // MARK: Frames

    /// Moves on one frame; at the end of a cycle decides what comes next.
    public func tick() {
        guard !reduceMotion else { frame = 0; return }
        let dt = animation.frameDuration
        frame += 1
        if let target = walkTarget, isWalking {
            let step = Self.walkSpeed * dt, d = target - x
            if abs(d) <= step { x = target; walkTarget = nil; setBase() } else { x += d > 0 ? step : -step }
        }
        if animation == .idle { idleFor += dt }
        if frame >= animation.frames { frame = 0; cycleEnded() }
    }

    private func cycleEnded() {
        if animation.isGesture {
            gestureCycles -= 1
            if gestureCycles <= 0 { setBase() }
            return
        }
        guard animation == .idle, mood == .calm, idleFor >= nextFlourish else { return }
        idleFor = 0
        nextFlourish = Self.flourishAfter.lowerBound + random() * (Self.flourishAfter.upperBound - Self.flourishAfter.lowerBound)
        if random() < 0.6 { wander() } else { gesture(random() < 0.5 ? .review : .waving, cycles: 1) }
    }

    /// Walks to somewhere else along the bottom.
    private func wander() {
        var target = random()
        // At least a short way, so it is seen to go somewhere.
        if abs(target - x) < 0.15 { target = x > 0.5 ? max(x - 0.3, 0) : min(x + 0.3, 1) }
        walkTarget = target
        start(target > x ? .runningRight : .runningLeft)
    }

    private func gesture(_ a: PetAnimation, cycles: Int) {
        walkTarget = nil
        gestureCycles = cycles
        start(a)
    }

    private func moodChanged() {
        guard !reduceMotion else { return }
        if mood == .trouble { gesture(.failed, cycles: 2) }
        else if !animation.isGesture { setBase() }   // a gesture under way ends first, then settles into the new mood
    }

    private func setBase() {
        walkTarget = nil
        switch mood {
        case .calm, .trouble: start(.idle)
        case .busy: start(.running)
        case .offline: start(.waiting)
        }
    }

    private func start(_ a: PetAnimation) {
        animation = a
        frame = 0
        if a == .idle { idleFor = 0 }
    }
}
