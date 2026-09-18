import Foundation

/// Omsætter et stykke samtale til ét skriftligt svar.
struct ReplyGenerator {

    struct Request {
        var utterances: [Utterance]
        var keywords: [String]
        var isTopicShift: Bool
        var length: ReplyLength
        var persona: String
        var effort: String
    }

    var apiKey: String
    var model: String
    /// Når nøglen mangler eller kaldet slår fejl, må appen hellere skrive en
    /// beskeden lokal formulering end ingenting.
    var allowLocalFallback: Bool

    func generate(_ request: Request) async throws -> ReplyRecord {
        let system = DanishReplyPrompt.system(length: request.length, persona: request.persona)
        let user = DanishReplyPrompt.userMessage(
            utterances: request.utterances,
            keywords: request.keywords,
            isTopicShift: request.isTopicShift
        )

        do {
            guard !apiKey.isEmpty else { throw ClaudeClient.ClientError.missingAPIKey }
            let client = ClaudeClient(apiKey: apiKey, model: model)
            let raw = try await client.complete(
                system: system,
                userMessage: user,
                maxTokens: request.length.maxTokens,
                effort: request.effort
            )

            guard let parsed = DanishReplyPrompt.parse(raw) else {
                // Modellen svarede INTET: der var ingen rød tråd værd at svare på.
                throw GeneratorError.nothingWorthSaying
            }

            return ReplyRecord(
                topic: parsed.topic ?? fallbackTopic(from: request.keywords),
                body: parsed.body,
                keywords: request.keywords,
                source: .model,
                utteranceCount: request.utterances.count
            )
        } catch GeneratorError.nothingWorthSaying {
            throw GeneratorError.nothingWorthSaying
        } catch {
            guard allowLocalFallback else { throw error }
            return localReply(for: request)
        }
    }

    enum GeneratorError: LocalizedError {
        case nothingWorthSaying

        var errorDescription: String? {
            switch self {
            case .nothingWorthSaying:
                return "Der var ingen rød tråd at svare på endnu."
            }
        }
    }

    // MARK: - Lokal nødformulering

    /// Uden netværk eller nøgle kan appen ikke formulere frit. Den her skriver en
    /// ærlig, kort replik ud fra de ord, der går igen — og er mærket som netop dét.
    private func localReply(for request: Request) -> ReplyRecord {
        let topic = fallbackTopic(from: request.keywords)
        let leading = request.keywords.prefix(3)

        let body: String
        switch leading.count {
        case 0:
            body = "Der bliver talt, men der er ikke rigtig nogen tråd i det endnu — lad os se, hvor det bærer hen."
        case 1:
            body = "Snakken kredser om \(leading[leading.startIndex]). Det er jo netop dér, det bliver interessant — spørgsmålet er bare, hvad der egentlig står på spil."
        default:
            let list = Array(leading)
            let joined = list.dropLast().joined(separator: ", ") + " og " + (list.last ?? "")
            body = "Det handler i bund og grund om \(joined). De to ting hænger tættere sammen, end man umiddelbart skulle tro, og det er nok dér, uenigheden i virkeligheden ligger."
        }

        return ReplyRecord(
            topic: topic,
            body: body,
            keywords: request.keywords,
            source: .local,
            utteranceCount: request.utterances.count
        )
    }

    private func fallbackTopic(from keywords: [String]) -> String {
        guard !keywords.isEmpty else { return "Samtale" }
        return keywords.prefix(3).joined(separator: ", ").capitalizedFirstLetter
    }
}

private extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
