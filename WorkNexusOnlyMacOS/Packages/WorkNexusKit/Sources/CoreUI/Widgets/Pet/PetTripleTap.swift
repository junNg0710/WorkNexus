/// Not in the Flutter app.
import SwiftUI

/// What three quick clicks on the pet do (the panic switch's alert), and whether that is on right now. While it is, a
/// single click waits a moment for the next before doing what it usually does, so the first click of three does not
/// bring the app forward; while it is off, a click acts at once.
public struct PetTripleTap {
    public var armed: () -> Bool
    public var run: () -> Void
    public init(armed: @escaping () -> Bool, run: @escaping () -> Void) { self.armed = armed; self.run = run }
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
