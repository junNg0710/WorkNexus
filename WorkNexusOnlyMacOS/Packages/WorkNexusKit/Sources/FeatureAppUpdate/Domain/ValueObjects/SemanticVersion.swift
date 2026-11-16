import Foundation

/// Ported from: lib/features/app_update/domain/usecases/check_for_update.dart (`_Version`).
/// `v?MAJOR.MINOR.PATCH[-pre][+build]`, ordered like semver except that pre-release identifiers compare as plain strings.
public struct SemanticVersion: Sendable, Comparable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public var isPrerelease: Bool { prerelease != nil }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$"#)

    public init?(_ value: String) {
        let ns = value as NSString
        guard let m = Self.pattern.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)),
              let a = Int(ns.substring(with: m.range(at: 1))), let b = Int(ns.substring(with: m.range(at: 2))),
              let c = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        major = a; minor = b; patch = c
        prerelease = m.range(at: 4).location == NSNotFound ? nil : ns.substring(with: m.range(at: 4))
    }

    public static func < (l: SemanticVersion, r: SemanticVersion) -> Bool {
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
