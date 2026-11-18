import Foundation
import Observation

/// What the TBChat character is doing: which animation and frame, and where it stands. It idles, waves when poked, jumps
/// when something is celebrated, shows how the app is doing (working / offline / in trouble), and now and then walks to
/// another spot or does a little something.
///
/// Two clocks: the sprite's frames advance with `tick()` (once per `frameDuration`), while its place while walking is a
/// function of time (`x(at:)`), read at the display's rate - so it glides instead of stepping once per sprite frame.
@MainActor @Observable
public final class PetDirector {
    /// How the app is doing, which sets what the character does when nothing else is going on: `attention` is something
    /// waiting for the user (a ticket for them, say); `offline` keeps it idling, the view dims it.
    public enum Mood: Equatable, Sendable { case calm, busy, offline, trouble, attention }

    /// A walk under way: from where to where, and when.
    public struct Walk: Equatable, Sendable {
        public var from: Double, to: Double
        public var start: Date
        public var duration: TimeInterval

        /// Where the character is at `date`: it eases away from `from` and into `to` (no jolt at either end).
        public func x(at date: Date) -> Double {
            let t = min(max(date.timeIntervalSince(start) / max(duration, 0.001), 0), 1)
            let eased = t * t * (3 - 2 * t)
            return from + (to - from) * eased
        }
        public func isOver(at date: Date) -> Bool { date.timeIntervalSince(start) >= duration }
    }

    public private(set) var animation: PetAnimation = .idle
    public private(set) var frame = 0
    /// Where the character stands when it is not walking: 0...1 across the room it has, left to right, and 0 (top) to 1 (bottom).
    public var x = 0.92
    public var y = 1.0
    /// The walk under way; nil while it stands.
    public private(set) var walk: Walk?
    public var mood: Mood = .calm { didSet { if mood != oldValue { moodChanged() } } }
    /// With reduced motion the character keeps still: its first frame, no walking, no gestures.
    public var reduceMotion = false
    /// How wide the room is, in points (the view says): a walk's time comes from its length on screen, so the character
    /// walks at one pace whatever the window's width.
    public var roomWidth: Double = 800
    /// Whether it walks about on its own now and then.
    public var canWander = true
    /// The pace of the sheet it is drawn from (the view says).
    public var timing: PetTiming = .steady
    /// Which way it looks (0 = up, clockwise, of `PetSpriteSheet.lookDirections`), for a sheet that can look; nil looks
    /// nowhere in particular. Only shown while it stands idling (`showsGaze`).
    public var gaze: Int?
    /// What it is saying, in a speech bubble, and until when (`say`); nil when it says nothing.
    public private(set) var speech: Speech?
    /// What goes on now, in words: shown while the pointer rests on it, so a reaction can be read after the fact.
    public var status: String?

    /// A line in a speech bubble, shown until `until`; `link` is what a click on it opens (a chat, a notification), if
    /// anything - opaque here, the app knows what it means.
    public struct Speech: Equatable, Sendable {
        public var text: String
        public var until: Date
        public var link: String?
    }

    /// Walking pace, in points per second.
    static let walkSpeed = 90.0
    /// Seconds of standing about before it does something of its own (mostly a walk to another spot).
    static let flourishAfter: ClosedRange<Double> = 8...20
    /// How long a line stays in its speech bubble.
    public static let speechDuration: TimeInterval = 6

    @ObservationIgnored private var idleFor = 0.0
    @ObservationIgnored private var nextFlourish: Double
    @ObservationIgnored private var gestureCycles = 0
    @ObservationIgnored private let random: () -> Double
    @ObservationIgnored private let now: () -> Date

    public init(random: @escaping () -> Double = { Double.random(in: 0..<1) }, now: @escaping () -> Date = { Date() }) {
        self.random = random; self.now = now
        nextFlourish = Self.flourishAfter.lowerBound + random() * (Self.flourishAfter.upperBound - Self.flourishAfter.lowerBound)
    }

    /// Where the character is at `date`, walking or not.
    public func x(at date: Date) -> Double { walk?.x(at: date) ?? x }

    public var frameDuration: TimeInterval { timing.duration(animation, frame: frame) }
    /// Whether it is looking somewhere rather than playing its idle frames.
    public var showsGaze: Bool { gaze != nil && animation == .idle && walk == nil && !reduceMotion }
    public var isWalking: Bool { animation == .runningLeft || animation == .runningRight }

    // MARK: Things that happen to it

    /// Poked (a click): waves.
    public func poke() { guard !reduceMotion else { return }; gesture(.waving, cycles: 1) }

    /// Something to celebrate (a bug resolved): jumps for joy.
    public func celebrate() { guard !reduceMotion else { return }; gesture(.jumping, cycles: 2) }

    /// Something new for the user (a chat message): waves at them, twice.
    public func notify() { guard !reduceMotion else { return }; gesture(.waving, cycles: 2) }

    /// A piece of work finished (a sync done): looks it over once.
    public func done() { guard !reduceMotion, !animation.isGesture else { return }; gesture(.review, cycles: 1) }

    /// Says `text` in a speech bubble for `seconds` (a newer line replaces it). Said even with reduced motion: it is
    /// how the user learns what a reaction was about.
    public func say(_ text: String, for seconds: TimeInterval = PetDirector.speechDuration, link: String? = nil) {
        speech = Speech(text: text, until: now().addingTimeInterval(seconds), link: link)
    }

    /// Stops saying what it says (the user opened it).
    public func hush() { speech = nil }

    /// The bubble's line: what it is saying, or - while the pointer rests on it - what goes on now. A line that opens
    /// something stays while the pointer is on the pet, so it can be clicked.
    public func bubble(hovering: Bool) -> String? {
        if speech?.link != nil { return speech?.text }
        return hovering ? (status ?? speech?.text) : speech?.text
    }

    /// What a click on the pet or its bubble opens now, if anything.
    public var link: String? { speech?.link }

    /// Dragged to a spot: stays there.
    public func place(x: Double, y: Double) {
        self.x = min(max(x, 0), 1); self.y = min(max(y, 0), 1)
        walk = nil
        if isWalking { setBase() }
    }

    // MARK: Frames

    /// Moves on one frame; at the end of a cycle decides what comes next.
    public func tick() {
        if let s = speech, now() >= s.until { speech = nil }
        guard !reduceMotion else { frame = 0; return }
        let dt = frameDuration
        frame += 1
        // The walk is over once its time is up: the character is at its target and goes back to what it was doing.
        if let w = walk, w.isOver(at: now()) { x = w.to; walk = nil; setBase(); return }
        if isStandingAbout { idleFor += dt }
        if frame >= animation.frames { frame = 0; cycleEnded() }
    }

    private func cycleEnded() {
        if animation.isGesture {
            gestureCycles -= 1
            if gestureCycles <= 0 { setBase() }
            return
        }
        // Whatever its mood, it walks to another spot now and then; only a calm pet also waves or looks things over
        // (in another mood a gesture would read as news).
        guard isStandingAbout, idleFor >= nextFlourish else { return }
        idleFor = 0
        nextFlourish = Self.flourishAfter.lowerBound + random() * (Self.flourishAfter.upperBound - Self.flourishAfter.lowerBound)
        if canWander, random() < 0.75 { wander() }
        else if mood == .calm { gesture(random() < 0.5 ? .review : .waving, cycles: 1) }
    }

    /// Playing its mood's own animation: no gesture, no walk.
    private var isStandingAbout: Bool { !animation.isGesture && !isWalking }

    /// Walks to somewhere else along the bottom.
    private func wander() {
        var target = random()
        // At least a short way, so it is seen to go somewhere.
        if abs(target - x) < 0.15 { target = x > 0.5 ? max(x - 0.3, 0) : min(x + 0.3, 1) }
        let points = abs(target - x) * max(roomWidth, 1)
        walk = Walk(from: x, to: target, start: now(), duration: max(points / Self.walkSpeed, 0.6))
        start(target > x ? .runningRight : .runningLeft)
    }

    private func gesture(_ a: PetAnimation, cycles: Int) {
        stopWalking()
        gestureCycles = cycles
        start(a)
    }

    private func moodChanged() {
        guard !reduceMotion else { return }
        if mood == .trouble { gesture(.failed, cycles: 2) }
        else if !animation.isGesture { setBase() }   // a gesture under way ends first, then settles into the new mood
    }

    /// A walk cut short leaves the character where it had got to.
    private func stopWalking() {
        if let w = walk { x = w.x(at: now()); walk = nil }
    }

    private func setBase() {
        stopWalking()
        switch mood {
        case .calm, .trouble, .offline: start(.idle)
        case .busy: start(.running)
        case .attention: start(.waiting)
        }
    }

    private func start(_ a: PetAnimation) {
        animation = a
        frame = 0
        if !a.isGesture, a != .runningLeft, a != .runningRight { idleFor = 0 }
    }
}
