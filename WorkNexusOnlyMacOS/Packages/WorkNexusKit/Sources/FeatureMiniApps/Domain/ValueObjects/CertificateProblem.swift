/// Ported from: lib/features/mini_apps/domain/value_objects/certificate_problem.dart
/// Why a site's certificate is refused, in the words the user is told.
public enum CertificateProblem: Sendable, Equatable {
    /// Expired, or not valid yet.
    case dates
    /// Issued for another site name.
    case name
    /// Not issued by an authority the computer trusts (self-signed, say).
    case authority
    /// Revoked, weak, or refused for another reason.
    case other

    /// What an error code (`net::ERR_CERT_DATE_INVALID`) says.
    public static func of(_ error: String) -> CertificateProblem {
        switch error {
        case "net::ERR_CERT_DATE_INVALID": .dates
        case "net::ERR_CERT_COMMON_NAME_INVALID": .name
        case "net::ERR_CERT_AUTHORITY_INVALID": .authority
        default: .other
        }
    }

    /// Whether `error` is a refused certificate, as opposed to any other page error (offline, refused connection).
    public static func isCertificateError(_ error: String) -> Bool { error.hasPrefix("net::ERR_CERT_") }

    /// Maps the `NSURLError` of a failed secure load (WKWebView) onto the Chromium-style code the rest of the feature speaks.
    public static func code(forURLErrorCode code: Int) -> String? {
        switch code {
        case -1201: "net::ERR_CERT_DATE_INVALID"            // NSURLErrorServerCertificateHasBadDate
        case -1202: "net::ERR_CERT_AUTHORITY_INVALID"       // NSURLErrorServerCertificateUntrusted
        case -1203: "net::ERR_CERT_AUTHORITY_INVALID"       // NSURLErrorServerCertificateHasUnknownRoot
        case -1204: "net::ERR_CERT_DATE_INVALID"            // NSURLErrorServerCertificateNotYetValid
        default: nil
        }
    }
}
