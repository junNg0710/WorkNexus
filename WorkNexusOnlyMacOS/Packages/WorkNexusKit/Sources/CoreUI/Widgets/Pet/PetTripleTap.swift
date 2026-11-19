/// Not in the Flutter app.
import SwiftUI

/// How the pet raises the panic switch's alert.
public enum PetAlertGesture: Equatable, Sendable {
    /// Pressing and holding the pet (without moving it) for `seconds`.
    case hold(seconds: Double)
    /// Two quick clicks on the pet.
    case doubleTap
    /// Three quick clicks on the pet.
    case tripleTap

    var holdSeconds: Double? { if case .hold(let s) = self { s } else { nil } }

    /// How many quick clicks raise it; nil for a hold.
    var tapsNeeded: Int? {
        switch self {
        case .hold: nil
        case .doubleTap: 2
        case .tripleTap: 3
        }
    }
}

/// What the pet's alert gesture does (the panic switch's alert), and which gesture is on right now (nil: none). While
/// clicks are, a single click waits a moment for the next before doing what it usually does, so the first click of the
/// run does not bring the app forward; otherwise a click acts at once.
public struct PetTripleTap {
    public var armed: () -> PetAlertGesture?
    public var run: () -> Void
    public init(armed: @escaping () -> PetAlertGesture?, run: @escaping () -> Void) { self.armed = armed; self.run = run }
}

private struct PetTripleTapKey: EnvironmentKey { static let defaultValue: PetTripleTap? = nil }
public extension EnvironmentValues {
    var petTripleTap: PetTripleTap? {
        get { self[PetTripleTapKey.self] }
        set { self[PetTripleTapKey.self] = newValue }
    }
}

/// Counts the clicks on the pet: `needed` within `gap` of each other run `alert`; fewer, once the next does not come in
/// time, run `single` once.
@MainActor
final class PetTapCounter {
    static let gap: Duration = .milliseconds(400)
    private var count = 0
    private var pending: Task<Void, Never>?

    /// - Parameter needed: the clicks that raise the alert (2 or 3); nil: none do, a click acts at once.
    func tap(needed: Int?, single: @escaping () -> Void, alert: @escaping () -> Void) {
        guard let needed else { reset(); single(); return }
        count += 1
        pending?.cancel()
        if count >= needed { reset(); alert(); return }
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.gap)
            guard !Task.isCancelled else { return }
            self?.reset()
            single()
        }
    }

    private func reset() { count = 0; pending?.cancel(); pending = nil }
}
