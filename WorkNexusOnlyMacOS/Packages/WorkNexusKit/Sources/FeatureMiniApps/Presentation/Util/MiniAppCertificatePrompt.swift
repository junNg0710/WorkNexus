import AppKit
import Foundation

/// Ported from: lib/features/mini_apps/presentation/util/mini_app_certificate_prompt.dart
/// Asks whether to trust a site whose certificate the system refused, in the words of `CertificateProblem`.
@MainActor
enum MiniAppCertificatePrompt {
    static func ask(origin: String, error: String) async -> Bool {
        let reason: String
        switch CertificateProblem.of(error) {
        case .dates: reason = String(localized: "certReasonDates")
        case .name: reason = String(localized: "certReasonName")
        case .authority: reason = String(localized: "certReasonAuthority")
        case .other: reason = String(format: String(localized: "certReasonOther"), error)
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "certPromptTitle")
        alert.informativeText = String(format: String(localized: "certPromptMessage"), origin, reason)
        alert.addButton(withTitle: String(localized: "certTrust"))
        alert.addButton(withTitle: String(localized: "cancel"))
        return await MiniAppPermissionPrompter.run(alert) == .alertFirstButtonReturn
    }
}
