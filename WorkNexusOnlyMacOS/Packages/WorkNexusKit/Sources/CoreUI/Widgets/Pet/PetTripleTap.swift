/// Not in the Flutter app.
import SwiftUI

/// How the pet raises the panic switch's alert.
public enum PetAlertGesture: Equatable, Sendable {
    /// Pressing and holding the pet (without moving it) for `seconds`.
    case hold(seconds: Double)
    /// Three quick clicks on the pet.
    case tripleTap

    var holdSeconds: Double? { if case .hold(let s) = self { s } else { nil } }
}

/// What the pet's alert gesture does (the panic switch's alert), and which gesture is on right now (nil: none). While
/// three clicks are, a single click waits a moment for the next before doing what it usually does, so the first click
/// of three does not bring the app forward; otherwise a click acts at once.
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

/// Counts the clicks on the pet: three within `gap` of each other run `triple`; fewer, once the next does not come in
/// time, run `single` once.
@MainActor
final class PetTapCounter {
    static let gap: Duration = .milliseconds(400)
    private var count = 0
    private var pending: Task<Void, Never>?

    func tap(armed: Bool, single: @escaping () -> Void, triple: @escaping () -> Void) {
        guard armed else { reset(); single(); return }
        count += 1
        pending?.cancel()
        if count >= 3 { reset(); triple(); return }
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.gap)
            guard !Task.isCancelled else { return }
            self?.reset()
            single()
        }
    }

    private func reset() { count = 0; pending?.cancel(); pending = nil }
}
