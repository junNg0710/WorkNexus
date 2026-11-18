import CoreDomain
import Foundation

/// HTTP seam (URLSession in production) so the service is testable without a network.
public protocol TranslationHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTranslationClient: TranslationHTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Ported from: lib/features/translation/data/api_translation_service.dart
/// Translates through any OpenAI-compatible `/chat/completions` endpoint with the user's own key (Gemini, Groq, OpenRouter, Ollama, …).
public final class ApiTranslationService: TranslationService, @unchecked Sendable {
    private let http: TranslationHTTPClient
    /// The configuration in force right now; read per call so a saved change applies without restarting.
    private let config: @Sendable () async -> TranslationApiConfig?
    private static let templateVersion = "api-v1"
    private let running = Locked<[String: Task<(Data, HTTPURLResponse), Error>]>([:])

    public init(http: TranslationHTTPClient = URLSessionTranslationClient(), config: @escaping @Sendable () async -> TranslationApiConfig?) {
        self.http = http; self.config = config
    }

    public func contentHash(_ source: TicketSource) -> String { FeatureTranslation.contentHash(source.title, source.body) }

    public func cancel(_ ticketId: String) async {
        running.withLock { $0.removeValue(forKey: ticketId) }?.cancel()
    }

    public func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String,
                          model: String?) async -> Outcome<TranslationRecord> {
        let language = translationLanguage(for: targetLang)
        let cfg = await config()
        switch await complete(key: ticketId, config: cfg, prompt: ticketPrompt(source, language.englishName)) {
        case .failure(let f): return .failure(f)
        case .success(let text):
            guard let parsed = extractTicketJson(text) else { return .failure(.parse("Could not parse the translation: \(text)")) }
            return .success(ticketRecord(parsed: parsed, ticketId: ticketId, source: source, sourceHash: sourceHash,
                                         lang: language.code, model: cfg?.model ?? "", templateVersion: Self.templateVersion))
        }
    }

    public func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> {
        let language = translationLanguage(for: targetLang)
        return await complete(key: key, prompt: textPrompt(text, language.englishName), model: model)
    }

    /// The model is the configured one: with an API key the user's setting is in charge.
    public func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> {
        let cfg = await config()
        switch await complete(key: key, config: cfg, prompt: prompt) {
        case .failure(let f): return .failure(f)
        case .success(let out):
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .failure(.parse("The model returned no text")) : .success(TextTranslation(trimmed, model: cfg?.model))
        }
    }

    private func complete(key: String, config: TranslationApiConfig?, prompt: String) async -> Outcome<String> {
        guard let config, config.isUsable else { return .failure(.auth("No translation API key is set up")) }
        let base = config.baseUrl.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = URL(string: "\(base)/chat/completions") else { return .failure(.validation("Invalid API base URL")) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty { req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization") }
        let payload: [String: Any] = ["model": config.model, "temperature": 0.2,
                                      "messages": [["role": "user", "content": prompt]]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let http = self.http
        let task = Task { try await http.send(req) }
        running.withLock { $0[key] = task }
        defer { running.withLock { $0[key] = nil } }
        do {
            let (data, response) = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard (200..<300).contains(response.statusCode) else { return .failure(Self.failure(status: response.statusCode, body: data)) }
            guard let text = Self.content(of: data) else { return .failure(.parse("The API reply held no message")) }
            return .success(text)
        } catch is CancellationError {
            return .failure(.network("Translation cancelled"))
        } catch let e as URLError where e.code == .cancelled {
            return .failure(.network("Translation cancelled"))
        } catch is URLError {
            return .failure(.network("Could not reach the translation API"))
        } catch {
            return .failure(.unexpected("Translation failed: \(error)"))
        }
    }

    static func content(of data: Data) -> String? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = body["choices"] as? [Any], let first = choices.first as? [String: Any],
              let message = first["message"] as? [String: Any] else { return nil }
        return message["content"] as? String
    }

    static func failure(status: Int, body: Data) -> Failure {
        let detail = errorDetail(body)
        let suffix = detail.map { ": \($0)" } ?? ""
        switch status {
        case 401, 403: return .auth("The translation API rejected the key\(suffix)")
        case 429: return .network("Translation rate limit reached — wait a moment or switch model\(suffix)")
        default: return .network("Translation API error \(status)\(suffix)")
        }
    }

    /// `error.message` as OpenAI-style APIs send it (some wrap it in a list).
    static func errorDetail(_ data: Data) -> String? {
        var obj = try? JSONSerialization.jsonObject(with: data)
        if let list = obj as? [Any], let first = list.first { obj = first }
        guard let body = obj as? [String: Any] else { return nil }
        let error = body["error"]
        let message = (error as? [String: Any])?["message"] ?? error
        guard let text = message as? String, !text.isEmpty else { return nil }
        return text.count <= 200 ? text : String(text.prefix(200)) + "…"
    }
}
