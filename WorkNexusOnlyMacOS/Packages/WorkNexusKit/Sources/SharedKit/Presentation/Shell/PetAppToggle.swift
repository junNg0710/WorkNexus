/// Not in the Flutter app.

/// What a click on the floating pet does to the app: hides it when it is in front with its window up, else brings it
/// forward.
public enum PetAppToggle {
    public static func hides(appActive: Bool, windowShown: Bool) -> Bool { appActive && windowShown }
}
