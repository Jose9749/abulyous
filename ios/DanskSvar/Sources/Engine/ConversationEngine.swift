import Combine
import Foundation
import UIKit

/// Bindeleddet: lytter, sporer emnet, afgør hvornår der skal svares, og lægger
/// svaret på skærmen. Al beslutningslogik om *hvornår* et svar må komme, ligger her.
@MainActor
final class ConversationEngine: ObservableObject {

    @Published private(set) var status: EngineStatus = .stopped
    /// Igangværende, ufærdig transskription. Vises kun i appen — aldrig som notifikation.
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var topic: TopicSnapshot?
    @Published private(set) var latestReply: ReplyRecord?
    @Published private(set) var lastErrorMessage: String?
    /// Hvor lang tid der er tilbage, før næste svar må komme. Nil = ingen spærring.
    @Published private(set) var secondsUntilNextReply: Int?
    @Published private(set) var utterancesHeard: Int = 0
    @Published private(set) var danishUtterancesAccepted: Int = 0

    private let settings: AppSettings
    private let history: HistoryStore
    private let notifications: NotificationCoordinator
    private let capture = DanishSpeechCapture()
    private let tracker = TopicTracker()
    private let languageGate = DanishLanguageGate()

    private var tickTimer: Timer?
    private var lastReplyAt: Date?
    private var lastRepliedTopicID: UUID?
    private var wordCountAtLastReply = 0
    private var isComposing = false
    private var pendingTopicShift = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(settings: AppSettings, history: HistoryStore, notifications: NotificationCoordinator) {
        self.settings = settings
        self.history = history
        self.notifications = notifications
        wireCapture()
    }

    var supportsOnDeviceDanish: Bool { capture.supportsOnDeviceDanish }

    // MARK: - Tænd og sluk

    func start() async {
        guard !status.isRunning else { return }
        status = .startingUp
        lastErrorMessage = nil

        let granted = await notifications.requestAuthorisation()
        guard granted else {
            status = .failed(reason: "notifikationer er slået fra")
            lastErrorMessage = "Appen må ikke sende notifikationer. Slå dem til under Indstillinger > DanskSvar > Beskeder."
            return
        }

        switch await DanishSpeechCapture.requestAuthorisations() {
        case .failure(let error):
            status = .failed(reason: "adgang mangler")
            lastErrorMessage = error.localizedDescription
            return
        case .success:
            break
        }

        tracker.reset()
        tracker.update(configuration: settings.topicConfiguration)
        utterancesHeard = 0
        danishUtterancesAccepted = 0
        pendingTopicShift = false

        do {
            try capture.start(onDeviceOnly: settings.onDeviceOnly)
            beginBackgroundTask()
            startTicking()
            status = .listening
        } catch {
            status = .failed(reason: "mikrofonen kunne ikke startes")
            lastErrorMessage = error.localizedDescription
        }
    }

    func stop() {
        capture.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        tracker.reset()
        endBackgroundTask()
        liveTranscript = ""
        topic = nil
        secondsUntilNextReply = nil
        status = .stopped
    }

    /// Fjerner svaret fra skærmen uden at slette det af historikken.
    func dismissCurrentReply() async {
        if let reply = latestReply {
            history.markRetired(reply.id)
        }
        await notifications.retireCurrent()
        latestReply = nil
    }

    // MARK: - Indkommende tale

    private func wireCapture() {
        capture.onPartialTranscript = { [weak self] text in
            self?.liveTranscript = text
        }
        capture.onUtterance = { [weak self] utterance in
            self?.handle(utterance)
        }
        capture.onError = { [weak self] error in
            self?.lastErrorMessage = error.localizedDescription
        }
    }

    private func handle(_ utterance: Utterance) {
        utterancesHeard += 1

        // Kun dansk tale tæller med. Alt andet ryger i gulvet her.
        guard languageGate.isDanish(utterance.text) else { return }
        danishUtterancesAccepted += 1
        liveTranscript = ""

        switch tracker.ingest(utterance) {
        case .started:
            pendingTopicShift = true
        case .extended:
            break
        }
        topic = tracker.current
    }

    // MARK: - Beslutningen om at svare

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard status.isRunning, !isComposing else { return }
        guard let topic = tracker.current else {
            secondsUntilNextReply = nil
            return
        }
        self.topic = topic

        let now = Date()

        // 1) Karensperiode efter et emneskift — det nye emne skal lige folde sig ud.
        guard now >= topic.eligibleAfter else {
            secondsUntilNextReply = Int(topic.eligibleAfter.timeIntervalSince(now).rounded(.up))
            return
        }

        // 2) Der skal være en pause i talen. Ellers svarer appen midt i en sætning.
        guard now.timeIntervalSince(topic.lastUtteranceAt) >= settings.settleDelay else {
            secondsUntilNextReply = nil
            return
        }

        // 3) Der skal være nok på bordet til, at der overhovedet er et emne.
        guard topic.utteranceCount >= settings.minimumUtterances,
              topic.wordCount >= settings.minimumWords
        else {
            secondsUntilNextReply = nil
            return
        }

        // 4) Der skal være en rød tråd. Løs, springende snak besvares ikke.
        guard topic.coherence >= settings.minimumCoherence else {
            secondsUntilNextReply = nil
            return
        }

        // 5) Der skal gå tid mellem svarene, så skærmen ikke bliver et maskingevær.
        if let lastReplyAt {
            let elapsed = now.timeIntervalSince(lastReplyAt)
            guard elapsed >= settings.minimumReplyInterval else {
                secondsUntilNextReply = Int((settings.minimumReplyInterval - elapsed).rounded(.up))
                return
            }
        }

        // 6) Samme emne som sidst? Så skal der være sagt noget nyt af betydning.
        if topic.id == lastRepliedTopicID {
            guard topic.wordCount - wordCountAtLastReply >= settings.newWordsBeforeFollowUp else {
                secondsUntilNextReply = nil
                return
            }
        }

        secondsUntilNextReply = nil
        compose(for: topic)
    }

    private func compose(for topic: TopicSnapshot) {
        isComposing = true
        status = .composing

        let generator = ReplyGenerator(
            apiKey: settings.apiKey,
            model: settings.model,
            allowLocalFallback: settings.allowLocalFallback
        )
        let request = ReplyGenerator.Request(
            utterances: tracker.recentUtterances(limit: 25),
            keywords: topic.keywords,
            isTopicShift: pendingTopicShift,
            length: settings.replyLength,
            persona: settings.persona,
            effort: settings.effort
        )

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isComposing = false
                if self.status == .composing { self.status = .listening }
            }

            do {
                let reply = try await generator.generate(request)
                await self.publish(reply, topic: topic)
            } catch ReplyGenerator.GeneratorError.nothingWorthSaying {
                // Ikke en fejl. Der var bare ikke noget at sige endnu — vent på mere.
                self.lastRepliedTopicID = topic.id
                self.wordCountAtLastReply = topic.wordCount
            } catch {
                self.lastErrorMessage = error.localizedDescription
                // Undgå at hamre løs på et kald, der fejler. Vent en runde.
                self.lastReplyAt = Date()
            }
        }
    }

    private func publish(_ reply: ReplyRecord, topic: TopicSnapshot) async {
        // Det forrige svar arkiveres, *inden* det forsvinder fra skærmen.
        if let previous = latestReply {
            history.markRetired(previous.id)
        }

        history.record(reply)
        await notifications.present(reply, timeSensitive: settings.timeSensitive)

        latestReply = reply
        lastReplyAt = Date()
        lastRepliedTopicID = topic.id
        wordCountAtLastReply = topic.wordCount
        pendingTopicShift = false
        lastErrorMessage = nil
    }

    // MARK: - Baggrund

    /// Giver iOS besked om, at appen har noget kørende, når den går i baggrunden.
    /// Selve lytningen holdes i live af `UIBackgroundModes: audio` i Info.plist.
    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "dansksvar.lytning") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
