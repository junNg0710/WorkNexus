/// Not in the Flutter app: the auth headers an OpenAI-compatible endpoint is called with.
import Foundation

/// Every endpoint takes the key as `Authorization: Bearer`. Anthropic's OpenAI-compatible endpoint (and its `/v1/models`)
/// also expects its own `x-api-key` and `anthropic-version` headers, so they are sent as well.
enum ApiRequestHeaders {
    static let anthropicVersion = "2023-06-01"

    /// The endpoint is Anthropic's (by host, so a provider saved as "custom" with that URL is treated the same).
    static func isAnthropic(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "anthropic.com" || host.hasSuffix(".anthropic.com")
    }

    static func apply(to request: inout URLRequest, apiKey: String) {
        guard !apiKey.isEmpty else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if isAnthropic(request.url) {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        }
    }
}
