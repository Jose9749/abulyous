import Foundation

/// Sporer "den røde tråd": holder styr på hvilket emne der bliver talt om, hvor
/// stramt det hænger sammen, og hvornår snakken skifter til noget andet.
final class TopicTracker {

    struct Configuration {
        /// Hvor hurtigt ældre ytringer mister vægt i emnets ordprofil.
        var decay: Double = 0.82
        /// Ligger en ytrings lighed med emnet under dette, tæller den som et misforhold.
        var shiftThreshold: Double = 0.14
        /// Antal misforhold i træk, før emnet erklæres skiftet.
        var shiftStreakRequired: Int = 2
        /// En pause længere end dette afslutter emnet af sig selv.
        var silenceTimeout: TimeInterval = 300
        /// Karensperiode efter et emneskift, før det nye emne må besvares.
        var switchGrace: TimeInterval = 20
        /// Ytringer med færre indholdsord end dette kan ikke udløse et emneskift.
        var minimumTokensToJudgeShift: Int = 3
    }

    enum Outcome {
        case extended(TopicSnapshot)
        case started(TopicSnapshot, previous: TopicSnapshot?)
    }

    private(set) var configuration: Configuration

    private var topicID = UUID()
    private var weights: [String: Double] = [:]
    private var utterances: [Utterance] = []
    private var similarities: [Double] = []
    private var missStreak = 0
    private var startedAt = Date()
    private var eligibleAfter = Date()

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func update(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Emnet som det ser ud lige nu, eller nil hvis der endnu ikke er sagt noget.
    var current: TopicSnapshot? {
        guard let last = utterances.last else { return nil }
        return TopicSnapshot(
            id: topicID,
            keywords: topKeywords(limit: 8),
            utteranceCount: utterances.count,
            wordCount: utterances.reduce(0) { $0 + $1.wordCount },
            startedAt: startedAt,
            lastUtteranceAt: last.timestamp,
            coherence: coherence,
            eligibleAfter: eligibleAfter
        )
    }

    /// De seneste ytringer i emnet, ældste først — det materiale svaret skrives ud fra.
    func recentUtterances(limit: Int = 25) -> [Utterance] {
        Array(utterances.suffix(limit))
    }

    /// Hvor stramt emnet hænger sammen. Gennemsnittet af de enkelte ytringers
    /// lighed med emnet, som det så ud, da de blev sagt.
    var coherence: Double {
        guard !similarities.isEmpty else { return 0 }
        // Den allerførste ytring i et emne har per definition ingen forgænger at
        // ligne, så den tæller ikke med.
        let scored = similarities.dropFirst()
        guard !scored.isEmpty else { return 0 }
        return scored.reduce(0, +) / Double(scored.count)
    }

    @discardableResult
    func ingest(_ utterance: Utterance) -> Outcome {
        let tokens = DanishText.contentTokens(in: utterance.text)
        let incoming = frequencies(of: tokens)

        // Første ytring overhovedet.
        guard !utterances.isEmpty else {
            beginTopic(with: utterance, tokens: incoming, similarity: 0, grace: false)
            return .started(currentOrEmpty(), previous: nil)
        }

        let gap = utterance.timestamp.timeIntervalSince(utterances[utterances.count - 1].timestamp)
        let similarity = DanishText.cosineSimilarity(incoming, weights)

        // For lang tavshed: samtalen er reelt en ny samtale.
        if gap > configuration.silenceTimeout {
            let previous = current
            beginTopic(with: utterance, tokens: incoming, similarity: 0, grace: true)
            return .started(currentOrEmpty(), previous: previous)
        }

        // Kun ytringer med nok kød på kan bære et emneskift. Korte indskud som
        // "ja, præcis" må ikke rive den røde tråd over.
        let judgeable = incoming.count >= configuration.minimumTokensToJudgeShift
        if judgeable {
            if similarity < configuration.shiftThreshold {
                missStreak += 1
            } else {
                missStreak = 0
            }
        }

        if missStreak >= configuration.shiftStreakRequired {
            let previous = current
            // Emnet skiftede ved den *forrige* ytring; start det nye emne med de
            // ytringer, der allerede handlede om det.
            let carryOver = Array(utterances.suffix(configuration.shiftStreakRequired - 1))
            beginTopic(with: utterance, tokens: incoming, similarity: 0, grace: true, carryOver: carryOver)
            return .started(currentOrEmpty(), previous: previous)
        }

        extendTopic(with: utterance, tokens: incoming, similarity: similarity)
        return .extended(currentOrEmpty())
    }

    /// Nulstiller sporingen — bruges når lytningen stoppes.
    func reset() {
        topicID = UUID()
        weights = [:]
        utterances = []
        similarities = []
        missStreak = 0
        startedAt = Date()
        eligibleAfter = Date()
    }

    // MARK: - Private

    private func beginTopic(
        with utterance: Utterance,
        tokens: [String: Double],
        similarity: Double,
        grace: Bool,
        carryOver: [Utterance] = []
    ) {
        topicID = UUID()
        weights = [:]
        utterances = []
        similarities = []
        missStreak = 0
        startedAt = carryOver.first?.timestamp ?? utterance.timestamp
        eligibleAfter = grace
            ? utterance.timestamp.addingTimeInterval(configuration.switchGrace)
            : utterance.timestamp

        for carried in carryOver {
            let carriedTokens = frequencies(of: DanishText.contentTokens(in: carried.text))
            extendTopic(with: carried, tokens: carriedTokens, similarity: 0)
        }
        extendTopic(with: utterance, tokens: tokens, similarity: similarity)
    }

    private func extendTopic(with utterance: Utterance, tokens: [String: Double], similarity: Double) {
        for key in weights.keys {
            weights[key] = (weights[key] ?? 0) * configuration.decay
        }
        for (term, count) in tokens {
            weights[term] = (weights[term] ?? 0) + count
        }
        // Hold profilen lille, så ældre irrelevante ord ikke hober sig op.
        if weights.count > 120 {
            let survivors = weights.sorted { $0.value > $1.value }.prefix(80)
            weights = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
        }

        utterances.append(utterance)
        similarities.append(similarity)
        if utterances.count > 60 {
            utterances.removeFirst(utterances.count - 60)
            similarities.removeFirst(similarities.count - 60)
        }
    }

    private func frequencies(of tokens: [String]) -> [String: Double] {
        var result: [String: Double] = [:]
        for token in tokens { result[token] = (result[token] ?? 0) + 1 }
        return result
    }

    private func topKeywords(limit: Int) -> [String] {
        weights.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        .prefix(limit)
        .map(\.key)
    }

    private func currentOrEmpty() -> TopicSnapshot {
        current ?? TopicSnapshot(
            id: topicID,
            keywords: [],
            utteranceCount: 0,
            wordCount: 0,
            startedAt: startedAt,
            lastUtteranceAt: startedAt,
            coherence: 0,
            eligibleAfter: eligibleAfter
        )
    }
}
