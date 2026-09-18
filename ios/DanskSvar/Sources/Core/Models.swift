import Foundation

/// Én færdiggjort ytring fra taleregistreringen.
struct Utterance: Identifiable, Hashable {
    let id: UUID
    let text: String
    let timestamp: Date
    /// Talegenkenderens egen tiltro til transskriptionen (0...1). 0 når den ikke oplyses.
    let confidence: Float

    init(id: UUID = UUID(), text: String, timestamp: Date = Date(), confidence: Float = 0) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.confidence = confidence
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
}

/// Et emne er en sammenhængende stribe ytringer — "den røde tråd".
struct TopicSnapshot: Identifiable, Hashable {
    let id: UUID
    /// De tungestvejende indholdsord i emnet, stærkeste først.
    let keywords: [String]
    let utteranceCount: Int
    let wordCount: Int
    let startedAt: Date
    let lastUtteranceAt: Date
    /// Hvor stramt ytringerne hænger sammen (0...1). Lav værdi = løs snak uden rød tråd.
    let coherence: Double
    /// Emnet må tidligst besvares efter dette tidspunkt (karensperiode ved emneskift).
    let eligibleAfter: Date

    /// En kort dansk overskrift udledt af nøgleordene, brugt indtil modellen leverer sin egen.
    var provisionalLabel: String {
        guard !keywords.isEmpty else { return "Samtale" }
        return keywords.prefix(3).joined(separator: ", ")
    }
}

/// Et svar som det er vist — eller har været vist — på låseskærmen.
struct ReplyRecord: Identifiable, Codable, Hashable {
    let id: UUID
    /// Modellens egen emneoverskrift, fx "Sommerhus i uge 29".
    var topic: String
    /// Selve svarteksten, der vises i notifikationen.
    var body: String
    var createdAt: Date
    /// Sat når svaret bliver fjernet fra låseskærmen til fordel for et nyere.
    var retiredAt: Date?
    /// Nøgleordene for det emne, svaret knytter sig til.
    var keywords: [String]
    /// Hvor svaret kom fra — modellen eller den lokale nødformulering.
    var source: Source
    /// Antal ytringer emnet bestod af, da svaret blev skrevet.
    var utteranceCount: Int

    enum Source: String, Codable {
        case model
        case local

        var danishLabel: String {
            switch self {
            case .model: return "Sprogmodel"
            case .local: return "Lokal nødformulering"
            }
        }
    }

    init(
        id: UUID = UUID(),
        topic: String,
        body: String,
        createdAt: Date = Date(),
        retiredAt: Date? = nil,
        keywords: [String] = [],
        source: Source = .model,
        utteranceCount: Int = 0
    ) {
        self.id = id
        self.topic = topic
        self.body = body
        self.createdAt = createdAt
        self.retiredAt = retiredAt
        self.keywords = keywords
        self.source = source
        self.utteranceCount = utteranceCount
    }
}

enum EngineStatus: Equatable {
    case stopped
    case startingUp
    case listening
    case composing
    case paused(reason: String)
    case failed(reason: String)

    var danishLabel: String {
        switch self {
        case .stopped: return "Slukket"
        case .startingUp: return "Starter op"
        case .listening: return "Lytter"
        case .composing: return "Formulerer svar"
        case .paused(let reason): return "På pause – \(reason)"
        case .failed(let reason): return "Fejl – \(reason)"
        }
    }

    var isRunning: Bool {
        switch self {
        case .listening, .composing, .startingUp: return true
        case .stopped, .paused, .failed: return false
        }
    }
}
