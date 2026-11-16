/// Why a browser's cookies were refused: the Keychain would not give out the browser's cookie key, or the system (Privacy:
/// Full Disk Access) would not let the app open the browser's files. The UI tells them apart by these messages.
public enum CookieReadRefusal {
    public static let keychain = "The keychain refused the password"
    public static let system = "The system refused access"
}
