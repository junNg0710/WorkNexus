/// Not in the Flutter app.
import CoreDomain

/// Whether a failure of work the app started by itself — refreshing a chat when it opens, marking it read, loading a page
/// while the list scrolls — is worth a toast. Losing the connection is not: the "Chat is offline" strip above the chat
/// already says so, and every chat opened or scrolled meanwhile used to add another error (two per chat opened). Such
/// failures go to the log instead. What the user does on purpose (send, pin, forward…) still reports every failure.
public enum BackgroundChatFailure {
    public static func shouldNotify(_ failure: Failure) -> Bool {
        switch failure {
        case .network, .cancelled: false
        default: true
        }
    }

    /// Shows `failure` through `notify` when it is worth it, logs it otherwise.
    public static func handle(_ failure: Failure, while work: String, notify: (Failure) -> Void) {
        if shouldNotify(failure) { notify(failure) } else { Diagnostics.info("chat", "\(work) failed: \(failure.message)") }
    }
}
