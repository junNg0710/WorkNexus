/// Not in the Flutter app.

/// What a click on the floating pet does to the app: brings it forward from another app; when it is already in front with
/// its window up, hides it, or — as the user chose (`goesBack`) — puts the app they were in before back over it.
public enum PetAppToggle {
    public enum Action: Equatable { case bringForward, hide, goBack }

    /// `hasPrevious`: an app the user was in before is still running.
    public static func action(appActive: Bool, windowShown: Bool, goesBack: Bool, hasPrevious: Bool) -> Action {
        guard appActive && windowShown else { return .bringForward }
        return goesBack && hasPrevious ? .goBack : .hide
    }
}
