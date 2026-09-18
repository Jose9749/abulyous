import Foundation

/// Minimal klient til Claude Messages API. Anthropic udgiver ingen officiel
/// Swift-SDK, så kaldet laves som almindelig HTTP mod `/v1/messages`.
struct ClaudeClient {

    enum ClientError: LocalizedError {
        case missingAPIKey
        case unauthorised
        case rateLimited
        case overloaded
        case declined(String?)
        case http(Int, String)
        case malformedResponse
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Der er ingen API-nøgle gemt. Indsæt din Anthropic-nøgle under Indstillinger."
            case .unauthorised:
                return "API-nøglen blev afvist. Kontrollér den under Indstillinger."
            case .rateLimited:
                return "For mange kald til API'et lige nu. Appen prøver igen ved næste emne."
            case .overloaded:
                return "Anthropics servere er overbelastede lige nu. Appen prøver igen ved næste emne."
            case .declined(let category):
                let suffix = category.map { " (\($0))" } ?? ""
                return "Modellen afviste at svare på dette indhold\(suffix)."
            case .http(let status, let body):
                return "Uventet svar fra API'et (HTTP \(status)): \(body.prefix(200))"
            case .malformedResponse:
                return "Svaret fra API'et kunne ikke læses."
            case .emptyResponse:
                return "API'et returnerede ingen tekst."
            }
        }
    }

    /// Claude Opus 5. Model-id'et har med vilje intet datosuffiks.
    static let defaultModel = "claude-opus-5"

    var apiKey: String
    var model: String = ClaudeClient.defaultModel
    var session: URLSession = .shared

    func complete(
        system: String,
        userMessage: String,
        maxTokens: Int,
        effort: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Slår serverside-fallback til: afviser Opus 5's sikkerhedsfiltre en
        // forespørgsel, køres den automatisk videre på en anden model i samme kald.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 90

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "output_config": ["effort": effort],
            "fallbacks": "default",
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.malformedResponse }

        guard (200 ..< 300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw ClientError.unauthorised
            case 429: throw ClientError.rateLimited
            case 529: throw ClientError.overloaded
            default:
                throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.malformedResponse
        }

        // Et afslag kommer som HTTP 200 med stop_reason "refusal" — indholdet skal
        // altså tjekkes, før der læses tekst ud af svaret.
        if let stopReason = json["stop_reason"] as? String, stopReason == "refusal" {
            let details = json["stop_details"] as? [String: Any]
            throw ClientError.declined(details?["category"] as? String)
        }

        guard let content = json["content"] as? [[String: Any]] else {
            throw ClientError.malformedResponse
        }

        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw ClientError.emptyResponse }
        return text
    }
}
