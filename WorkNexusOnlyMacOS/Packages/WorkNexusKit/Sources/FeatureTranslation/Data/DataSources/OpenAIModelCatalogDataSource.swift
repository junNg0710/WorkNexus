import CoreDomain
import Foundation

/// Ported from: lib/features/translation/data/datasources/openai_model_catalog_datasource.dart
/// Reads `GET {baseUrl}/models`, the listing every OpenAI-compatible endpoint (Gemini, Groq, OpenRouter, Ollama) serves.
/// Anthropic's `/v1/models` has the same `data[].id` shape but pages by 20 and wants its own headers (macOS only).
public struct OpenAIModelCatalogDataSource: TranslationApiModelCatalog {
    private let http: TranslationHTTPClient
    public init(http: TranslationHTTPClient = URLSessionTranslationClient()) { self.http = http }

    /// Models that cannot answer a chat prompt; Gemini, OpenAI, Mistral and xAI list them alongside the chat ones.
    private static let nonChat = try! NSRegularExpression(
        pattern: "embed|tts|whisper|image|veo|aqa|moderation|dall-e|realtime|transcribe|audio|sora|ocr", options: .caseInsensitive)

    public func listModels(baseUrl: String, apiKey: String) async -> Outcome<[String]> {
        let base = baseUrl.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard var url = URL(string: "\(base)/models") else { return .failure(.validation("Invalid API base URL")) }
        // Anthropic returns 20 models a page unless asked for more (its maximum is 1000).
        if ApiRequestHeaders.isAnthropic(url) { url = URL(string: "\(base)/models?limit=1000") ?? url }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        ApiRequestHeaders.apply(to: &req, apiKey: apiKey)
        do {
            let (data, response) = try await http.send(req)
            if response.statusCode == 401 || response.statusCode == 403 { return .failure(.auth("The API rejected the key")) }
            guard (200..<300).contains(response.statusCode) else { return .failure(.network("Could not load the model list")) }
            guard let ids = Self.ids(of: data) else { return .failure(.parse("The model list could not be read")) }
            return .success(ids)
        } catch is URLError {
            return .failure(.network("Could not load the model list"))
        } catch {
            return .failure(.unexpected("Could not load the model list"))
        }
    }

    /// `data[].id` from the reply. Gemini prefixes ids with `models/`, which its chat endpoint does not take back.
    static func ids(of data: Data) -> [String]? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let list = body["data"] as? [Any] else { return nil }
        var ids = Set<String>()
        for entry in list {
            guard let m = entry as? [String: Any], let id = m["id"] as? String else { continue }
            let clean = id.hasPrefix("models/") ? String(id.dropFirst("models/".count)) : id
            if nonChat.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) == nil { ids.insert(clean) }
        }
        return ids.sorted()
    }
}
