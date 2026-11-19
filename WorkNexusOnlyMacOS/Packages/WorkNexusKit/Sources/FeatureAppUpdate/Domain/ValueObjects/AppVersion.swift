import Foundation

/// Ported from: lib/features/app_update/domain/value_objects/app_version.dart
/// A release version (`1.4.1`, `v1.5.0-beta.1`, `v1.9.5+mac`), ordered as semver orders them: a pre-release sorts before
/// its release, and the build metadata (`+mac`, which marks the native app's releases) plays no part in the order —
/// `v1.9.5+mac` is the same version as the running `1.9.5`. Pre-release identifiers compare as plain strings.
public struct AppVersion: Sendable, Comparable, Hashable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    /// What follows `+` (`mac`); nil when the tag has none.
    public let build: String?

    public var isPrerelease: Bool { prerelease != nil }

    /// `v1.9.5` — the `vX.Y.Z[-pre]` part only, as a heading or a pill shows it.
    public var tag: String { "v\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "") }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$"#)

    public init?(_ value: String) {
        let ns = value as NSString
        guard let m = Self.pattern.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)),
              let a = Int(ns.substring(with: m.range(at: 1))), let b = Int(ns.substring(with: m.range(at: 2))),
              let c = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        major = a; minor = b; patch = c
        prerelease = m.range(at: 4).location == NSNotFound ? nil : ns.substring(with: m.range(at: 4))
        build = m.range(at: 5).location == NSNotFound ? nil : ns.substring(with: m.range(at: 5))
    }

    /// Equal when they order the same: the build metadata is ignored.
    public static func == (l: AppVersion, r: AppVersion) -> Bool {
        l.major == r.major && l.minor == r.minor && l.patch == r.patch && l.prerelease == r.prerelease
    }

    public func hash(into h: inout Hasher) { h.combine(major); h.combine(minor); h.combine(patch); h.combine(prerelease) }

    public static func < (l: AppVersion, r: AppVersion) -> Bool {
        if l.major != r.major { return l.major < r.major }
        if l.minor != r.minor { return l.minor < r.minor }
        if l.patch != r.patch { return l.patch < r.patch }
        switch (l.prerelease, r.prerelease) {
        case (nil, _): return false                 // a stable build is never below the same version's pre-release
        case (_?, nil): return true
        case let (a?, b?): return a < b
        }
    }
}
