/// Ported from: lib/core/util/fireworks.dart
import CoreGraphics
import Foundation

/// One spark of a firework: where its burst is, which way and how fast it flies, when its burst goes off (as a fraction of
/// the show) and its colour slot (an index into the caller's palette).
public struct FireworkSpark: Equatable, Sendable {
    public var origin: CGPoint
    public var angle: Double
    public var speed: Double
    public var start: Double
    public var colour: Int
}

/// Where a spark is at a moment of the show: its position, opacity, and how far through its own life it is.
public struct FireworkFrame: Equatable, Sendable {
    public var at: CGPoint
    public var opacity: Double
    public var life: Double
}

public enum Fireworks {
    /// How long one show runs (seconds), and how long each burst lives within it (a fraction of the show).
    public static let duration: TimeInterval = 3.2
    static let burstLife = 0.4
    /// Pulls sparks down, in points per second squared.
    static let gravity = 260.0

    /// The sparks of a show over an area of `size`: `bursts` bursts across the upper part of the area, going off in quick,
    /// overlapping succession. `seed` makes a show repeatable.
    public static func sparks(in size: CGSize, seed: UInt64, bursts: Int = 12, sparksPerBurst: Int = 48, colours: Int = 5) -> [FireworkSpark] {
        var rng = SplitMix64(seed: seed)
        var out: [FireworkSpark] = []
        for b in 0..<bursts {
            let origin = CGPoint(x: size.width * (0.08 + rng.next01() * 0.84), y: size.height * (0.1 + rng.next01() * 0.45))
            // Spread over the show, a little irregular so bursts overlap.
            let start = (Double(b) + rng.next01() * 0.6) * (1 - burstLife) / Double(bursts)
            let colour = Int(rng.next01() * Double(colours)) % colours
            for i in 0..<sparksPerBurst {
                out.append(FireworkSpark(
                    origin: origin,
                    angle: Double(i) * 2 * .pi / Double(sparksPerBurst) + (rng.next01() - 0.5) * 0.2,
                    speed: 160 + rng.next01() * 220,
                    start: start,
                    // Mostly the burst's colour, a few of the next for sparkle.
                    colour: rng.next01() < 0.8 ? colour : (colour + 1) % colours))
            }
        }
        return out
    }

    /// Where `spark` is at `t` (0-1 through the show); nil before its burst or after it has burnt out.
    public static func frame(of spark: FireworkSpark, at t: Double) -> FireworkFrame? {
        let local = (t - spark.start) / burstLife
        guard local >= 0, local <= 1 else { return nil }
        let seconds = local * burstLife * duration
        let at = CGPoint(x: spark.origin.x + cos(spark.angle) * spark.speed * seconds,
                         y: spark.origin.y + sin(spark.angle) * spark.speed * seconds + 0.5 * gravity * seconds * seconds)
        return FireworkFrame(at: at, opacity: 1 - local * local, life: local)
    }
}

/// A small seeded generator, so a show is repeatable (Dart `math.Random(seed)`).
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// A double in [0, 1).
    mutating func next01() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
